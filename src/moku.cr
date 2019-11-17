require "dotenv"
Dotenv.load

require "http"

require "./route"
require "./database"
require "./activity_pub"
require "./sign"
require "./signup"

require "./moku/config"

require "./moku/api"
require "./services/send_activity"
require "./services/webfinger"

module Moku
  class App
    include HTTP::Handler
    include Route

    def call(context)
      route context do |r, response, session|
        r.on "nodeinfo" { return API::NodeInfo.new.call context }
        r.on ".well-known" { return WellKnown.new.call context }
        return API.new.call(context) if r.json?

        if current_user_id = session["user_id"]?
          current_user = DB::GetLocalAccountWithID[current_user_id.as_s]
        end

        render "app_header"

        if (current_user_id = session["user_id"]?) && (current_user = DB::GetLocalAccountWithID[current_user_id.as_s])
          r.on "home" do
            render "new_note"
            DB::GetTimelineFor.call current_user_id.as_s do |(note, author, boosted_by, attachments)|
              render "timeline/entry"
            end
          end

          r.on "notifications" do
            # The notifications stream is the stream with the same ID as the user
            boosted_by = nil
            DB::GetNotesInStream.call current_user_id.as_s do |(note, author, attachments)|
              render "timeline/entry"
            end
          end

          r.on "new_note" do
            r.post do
              if body = r.body
                params = HTTP::Params.parse(body.gets_to_end)
                url = URI.parse("#{current_user_id.as_s}/notes/#{UUID.random}")
                created_at = Time.utc
                to = [PublicStreamURL.to_s]
                cc = [current_user.followers_url.to_s]
                sensitive = false

                note = DB::PostNoteFromAccount[
                  account_id: current_user.id,
                  id: url,
                  content: params["content"],
                  created_at: created_at,
                  url: url,
                  to: to,
                  cc: cc,
                  sensitive: sensitive,
                ]

                followers = DB::GetFollowersForAccount[current_user.handle]
                activity = ActivityPub::Activity.new(
                  id: URI.parse("#{url}/activity"),
                  type: "Create",
                  actor: current_user.id,
                  published: created_at,
                  to: to,
                  cc: cc,
                  object: ActivityPub::Object.new(
                    id: url,
                    type: "Note",
                    published: created_at,
                    url: url,
                    attributed_to: current_user.id,
                    to: to,
                    cc: cc,
                    sensitive: sensitive,
                    content: params["content"],
                  ),
                )
                keypair = DB::GetKeyPairForAccount[current_user.id]

                followers.each do |follower|
                  spawn do
                    case f = follower
                    when Account
                      puts "Federating note to #{f.id}"
                      Services::SendActivity[activity, f.shared_inbox, keypair]
                    when PartialAccount
                      account = Services::FetchRemoteAccount.new.call follower.id
                      Services::SendActivity[activity, account.shared_inbox, keypair]
                    end
                  end
                end

                response.redirect r.headers["Referer"]? || "/home"
              else
                response << "Request must include a body"
                response.status = HTTP::Status::BAD_REQUEST
              end
            end
          end

          r.on "logout" do
            r.delete do
              session.delete "user_id"
              response.redirect "/"
            end
          end

          r.post "follow" do
            if body = r.body
              params = HTTP::Params.parse(body.gets_to_end)
              account_id = params["account_id"]

              DB::RequestToFollowUser[current_user.handle, account_id]

              account = Services::FetchRemoteAccount.new.call(URI.parse(account_id))

              Services::SendActivity[
                ActivityPub::Activity.new(
                  id: URI.parse("#{current_user_id}/follows/#{UUID.random}"),
                  type: "Follow",
                  actor: current_user.id,
                  object: account.id,
                ),
                account.inbox_url.not_nil!,
                DB::GetKeyPairForAccount[current_user.id],
              ]
              response.redirect "/home"
            else
              response.status = HTTP::Status::BAD_REQUEST
            end
          end
        end

        r.on "login" do
          login_error = nil

          r.get { render "login" }
          r.post do
            if body = r.body
              params = HTTP::Params.parse(body.gets_to_end)
              if (user = DB::GetLocalAccountWithEmail[params["email"]]) && user.password.verify(params["password"])
                session["user_id"] = user.id.to_s
                response.redirect "/home"
              else
                login_error = "Invalid email or password"
                render "login"
              end
            else
              response << "<h2>Must supply post body</h2>"
              response.status = HTTP::Status::BAD_REQUEST
            end
          end
        end

        r.on "signup" { SignUp.new.call context }
        r.on "users" { Users.new.call context }

        r.on "search" do
          Search.new.call context
        end

        r.root do
          if session["user_id"]?
            response.redirect "/home"
          else
            response.redirect "/login"
          end
        end

        r.miss { render "not_found" }

        render "app_footer"
      end
    end
  end

  struct Search
    include Route

    def call(context)
      route context do |r, response|
        if query = r.params["query"]?
          results = search_for(query)
        else
          results = Array({Result, Account?}).new
        end

        render "search"
      end
    end

    def search_for(query : String) : Array({Result, Account?})
      case query
      when %r{\Ahttps://}
        id = URI.parse(query)
        results = [{Services::FetchRemoteAccount.new.call(id), nil}] of {Result, Account?}
      when /\A@?(\w+)@(\w+(\.\w+)*)/ # @foo@bar.baz
        # handle: $1, domain: $2
        finger = Services::Webfinger.new.call("#{$1}@#{$2}")
        link = finger.links.find { |link| link.type =~ /json/ }
        if link && link.href
          results = search_for(link.href.to_s)
        else
          raise UnprocessableResult.new("Cannot find JSON link with a remote href", finger)
        end
      else
        results = DB::Search[query]
      end

      results
    end

    private def show(note : Note, author : Account, response)
      render "search/note"
    end

    private def show(account : Account, _mehg : Nil, response)
      render "search/account"
    end

    private def show(result : Note, account : Nil, response)
      raise InvalidResult.new("Received a note with no author: #{result.inspect}")
    end

    private def show(result : Account, account : Account, response)
      raise InvalidResult.new("Received an account with another account? #{result.inspect} - #{account.inspect}")
    end

    alias Result = ::Note | ::Account

    class InvalidResult < Exception
    end
    class UnprocessableResult < Exception
      getter finger_result
      def initialize(message, @finger_result : Services::Webfinger::Result)
        super message
      end
    end
  end

  struct Users
    include Route

    def call(context)
      route context do |r, response, session|
        r.root do
          
        end

        r.on :handle do |handle|
          response << <<-HTML
            <!doctype html>
            <title>Moku</title>
            <h1>#{handle}</h1>
            <p>#{session["user_id"]?.inspect}</p>
          HTML
        end
      end
    end
  end

  struct WellKnown
    include Route

    def call(context)
      route context do |r, response|
        r.on "webfinger" do
          if resource = r.params["resource"]?
            handle, host = resource.split("@", 2)
            handle = handle.sub(/\Aacct:/, "")
            if account = DB::GetLocalAccountWithHandle[handle]
              response.headers["Content-Type"] = "application/jrd+json"
              response.headers["Date"] = Time::Format::HTTP_DATE.format(Time.utc)
              {
                subject: "#{"acct:" unless resource.starts_with? "acct:"}#{resource}",
                aliases: {
                  account.id,
                },
                links: {
                  {
                    rel: "http://webfinger.net/rel/profile-page",
                    type: "text/html",
                    href: "https://#{host}/users/#{handle}"
                  },
                  {
                    rel: "self",
                    type: "application/activity+json",
                    href: "https://#{host}/users/#{handle}"
                  },
                },
              }.to_json response
            else
              response.status = HTTP::Status::NOT_FOUND
            end
          else
            response.status = HTTP::Status::NOT_FOUND
          end
        end

        r.on "nodeinfo" do
          response.headers["Content-Type"] = "application/json"
          {
            "links": [
              {
                "rel": "http://nodeinfo.diaspora.software/ns/schema/2.0",
                "href": "#{SELF}/nodeinfo/2.0",
              }
            ]
          }.to_json response
        end
      end
    end
  end
end

require "amqp-client"
spawn do
  AMQP::Client.start(ENV["AMQP_URL"]? || "amqp://guest:guest@localhost") do |amqp|
    amqp.channel do |channel|
      exchange = channel.exchange("activities", "fanout")

      puts "Beginning message loop"
      loop do
        activity = Moku::ACTIVITY_QUEUE.receive
        exchange.publish activity.to_json, ""
      end
    end
  end
end

server = HTTP::Server.new([
  HTTP::LogHandler.new,
  HTTP::MethodTranslation.new,
  HTTP::Session::RedisStore.new(
    key: "moku_session",
  ),
  Moku::App.new,
])

port = ENV.fetch("PORT", "5000").to_i
puts "Listening on #{port}..."
server.listen "0.0.0.0", port

module HTTP
  class MethodTranslation
    include HTTP::Handler

    def call(context)
      request = context.request
      if (body = request.body) && request.headers["Content-Type"]? == "application/x-www-form-urlencoded"
        body_content = body.gets_to_end
        params = HTTP::Params.parse(body_content)
        if method = params["@method"]?
          request.method = method
        end

        request.body = IO::Memory.new(body_content)
      end


      call_next context
    end
  end
end
