require "dotenv"
unless ENV["SKIP_DOTENV"]?
  Dotenv.load
end

require "http"
require "logger"
require "awscr-signer"
require "awscr-s3"

require "./route"
require "./database"
require "./activity_pub"
require "./sign"
require "./signup"

require "./moku/config"

require "./moku/api"
require "./services/send_activity"
require "./services/webfinger"

require "./file_upload"

require "redis"
class Cache
  def initialize(@redis : Redis::PooledClient, @logger : Logger)
  end

  def fetch(key, response, ttl : Time::Span = 1.hour, &)
    status = nil

    if value = @redis.get(key)
      status = "hit!"
      response << value
    else
      status = "miss!"
      io = IO::Memory.new
      yield io
      io.rewind
      IO.copy io, response
      @redis.set(key, io.to_s, ex: ttl.total_seconds.to_i)
    end

    @logger.debug { "Cache.fetch(#{key.inspect}, ttl: #{ttl.inspect}) : #{status}" }
  end
end
logger = Logger.new(STDOUT)
CACHE = Cache.new(Redis::PooledClient.new(url: ENV["CACHE_REDIS_URL"]?), logger: logger)

module Moku
  class App
    include HTTP::Handler
    include Route

    def call(context)
      route context do |r, response, session|
        r.get "health" { return }
        r.on "nodeinfo" { return API::NodeInfo.new.call context }
        r.on ".well-known" { return WellKnown.new.call context }
        r.on "api" { return API.new.call(context) }
        return API.new.call(context) if r.json?

        if current_user_id = session["user_id"]?
          current_user = DB::GetLocalAccountWithID[current_user_id.as_s]
        end

        render_nav_link = Proc(String, String, String, String).new do |path, label, icon|
          %{<a href="#{path}"><span class="nav-icon">#{icon}</span> <span class="nav-label">#{label}</span></a>}
        end
        render "app_header"

        if current_user_id && current_user
          r.on "admin" { Admin.new(current_user).call context }

          r.get "home" do
            render "new_note"

            newest_timestamp = nil
            oldest_timestamp = nil

            response.flush
            # CACHE.fetch "timeline/#{current_user_id.as_s}/older_than=#{r.params["older_than"]?}/newer_than=#{r.params["newer_than"]?}", response, ttl: 5.seconds do |response|
              DB::GetTimelineFor.call(
                user_id: current_user_id.as_s,
                older_than: r.params["older_than"]?.try { |timestamp| Time.unix(timestamp.to_i) },
                newer_than: r.params["newer_than"]?.try { |timestamp| Time.unix(timestamp.to_i) },
              ) do |(note, author, boosted_by, attachments, boosted_at, poll_options, i_liked, i_boosted)|
                if newest_timestamp.nil?
                  newest_timestamp = boosted_at || note.created_at

                  render "timeline/newer_entries"
                end

                render "timeline/entry"

                oldest_timestamp = boosted_at || note.created_at
              end

              if oldest_timestamp
                render "timeline/older_entries"
              end
            # end
          end

          r.get "notifications" do
            # Notifications can't be boosted but the template expects this variable
            boosted_by = nil

            # The notifications stream is the stream with the same ID as the user
            DB::GetNotesInStream.call current_user_id.as_s, current_user.id do |(note, author, attachments, poll_options, i_liked, i_boosted)|
              render "timeline/entry"
            end
          end

          r.on "new_note" do
            r.post do
              if body = r.body
                files = Array(FileUpload).new

                if r.headers["Content-Type"]? =~ %r{multipart/form-data}
                  params = HTTP::Params.new

                  HTTP::FormData.parse(r) do |part|
                    case name = part.name
                    when "upload"
                      next if part.filename.not_nil!.empty?
                      file_content_type = part.headers["Content-Type"]
                      file = File.tempfile(part.filename) do |file|
                        IO.copy part.body, file
                      end
                      extension = File.extname(part.filename || "file.#{file_content_type.gsub(%r{\A.*/}, "")}")
                      id = UUID.random
                      key = "media_attachments/#{current_user.handle}/#{id}/original#{extension}"
                      files << FileUpload.new(
                        file: file,
                        key: key,
                        content_type: file_content_type,
                      )
                      spawn do
                        client = Awscr::S3::Client.new(AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, endpoint: S3_ENDPOINT)
                        uploader = Awscr::S3::FileUploader.new(client)

                        File.open(file.path, "r") do |file|
                          unless uploader.upload(S3_BUCKET, key, file, { "x-amz-acl" => "public-read" })
                            # TODO: Figure out a better exception here
                            raise uploader.inspect
                          end
                        end
                      end
                    else
                      params[name] = part.body.gets_to_end
                    end
                  end
                else
                  params = HTTP::Params.parse(body.gets_to_end)
                end
                url = URI.parse("#{current_user_id.as_s}/notes/#{UUID.random}")
                created_at = Time.utc
                to = [PublicStreamURL.to_s]
                cc = [current_user.followers_url.to_s]
                sensitive = false
                if in_reply_to = params["in_reply_to"]?
                  in_reply_to_id = URI.parse(in_reply_to)

                  previous = DB::GetNoteWithID[in_reply_to_id].not_nil! # We should have the note we're replying to
                  to = (to + previous.to).uniq
                  cc = (cc + previous.cc).uniq
                end

                note = DB::PostNoteFromAccount[
                  account_id: current_user.id,
                  id: url,
                  content: params["content"].gsub(/</, "&lt;"),
                  created_at: created_at,
                  url: url,
                  in_reply_to: in_reply_to_id,
                  to: to,
                  cc: cc,
                  sensitive: sensitive,
                  attachments: files.map { |file|
                    ActivityPub::Object.new(
                      type: "Document",
                      url: URI.parse("#{S3_CDN_URL}/#{file.key}"),
                      media_type: file.content_type,
                    )
                  },
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
                      puts "Federating note to #{f.shared_inbox}"
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

          r.post "unfollow" do
            if body = r.body
              params = HTTP::Params.parse(body.gets_to_end)
              account_id = URI.parse(params["account_id"])

              DB::UnfollowAccount[current_user.id, account_id]

              account = Services::FetchRemoteAccount.new.call(account_id)

              Services::SendActivity[
                ActivityPub::Activity.new(
                  id: URI.parse("#{current_user_id}/undo/#{UUID.random}"),
                  type: "Undo",
                  actor: current_user.id,
                  object: ActivityPub::Activity.new(
                    id: URI.parse("#{current_user_id}/follows/#{UUID.random}"),
                    type: "Follow",
                    actor: current_user.id,
                    object: account.id,
                  ),
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

        r.on "notes" do
          r.on :id do |id_string|
            id = URI.parse(URI.decode_www_form(id_string))

            r.is do
              DB::GetThreadFor.call id, current_user do |note, author, attachments, i_liked, i_boosted|
                render "notes/note"
              end

              spawn do
                Services::FetchReplyable.new.call id
              end
            end

            if current_user
              r.post "like" do
                liked = DB::IsAlreadyLikedBy[id, current_user]
                author = DB::AuthorOf[id]
                keypair = DB::GetKeyPairForAccount[current_user.id]

                activity = ActivityPub::Activity.new(
                  id: URI.parse("#{SELF}/likes/#{UUID.random}"),
                  type: "Like",
                  actor: current_user.id,
                  object: id,
                )

                if liked
                  activity = ActivityPub::Activity.new(
                    id: URI.parse("#{SELF}/undo/#{UUID.random}"),
                    type: "Undo",
                    actor: current_user.id,
                    object: activity,
                  )
                end

                Services::SendActivity[activity, author.inbox_url.not_nil!, keypair]

                if liked
                  DB::Unlike[current_user.id, id]
                else
                  DB::Like[current_user.id, id]
                end

                response.redirect r.headers["referer"]? || "/notes/#{URI.encode_www_form(id.to_s)}"
              end

              r.post "boost" do
                boosted = DB::IsAlreadyBoostedBy[id, current_user]
                author = DB::AuthorOf[id]
                keypair = DB::GetKeyPairForAccount[current_user.id]

                activity = ActivityPub::Activity.new(
                  id: boosted || URI.parse("#{SELF}/boosts/#{UUID.random}"),
                  type: "Announce",
                  actor: current_user.id,
                  object: id,
                  to: [PublicStreamURL.to_s],
                  cc: [
                    current_user.followers_url.to_s,
                    author.inbox_url.not_nil!.to_s,
                  ],
                )

                if boosted
                  activity = ActivityPub::Activity.new(
                    id: URI.parse("#{SELF}/undo/#{UUID.random}"),
                    type: "Undo",
                    actor: current_user.id,
                    object: activity,
                  )
                end

                pp JSON.parse(activity.to_json)
                Services::SendActivity[activity, author.inbox_url.not_nil!, keypair]
                followers = DB::GetFollowersForAccount[current_user.handle]
                followers.each do |follower|
                  spawn do
                    case f = follower
                    when Account
                      puts "Federating boost to #{f.id}"
                      Services::SendActivity[activity, f.shared_inbox, keypair]
                    when PartialAccount
                      account = Services::FetchRemoteAccount.new.call follower.id
                      Services::SendActivity[activity, account.shared_inbox, keypair]
                    end
                  end
                end

                if boosted
                  DB::UndoBoost[current_user.id, id]
                else
                  note = ActivityPub::Object.from_json(ActivityPub.get(id).body)
                  DB::BoostNote[current_user.id, note, activity]
                end

                response.redirect r.headers["referer"]? || "/notes/#{URI.encode_www_form(id.to_s)}"
              end
            end
          end

          r.miss do
            render "not_found"
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
          Search.new(current_user).call context
        end

        r.get "federated_timeline" do
          # Notifications can't be boosted but the template expects this variable
          boosted_by = nil

          # The notifications stream is the stream with the same ID as the user
          DB::GetNotesInStream.call "https://www.w3.org/ns/activitystreams#Public", current_user.try(&.id) do |(note, author, attachments, poll_options, i_liked, i_boosted)|
            render "timeline/entry"
            response.flush
          end
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

    def initialize(@current_user : LocalAccount?)
    end

    def call(context)
      route context do |r, response|
        r.root do
          if query = r.params["query"]?
            results = search_for(query)
          else
            results = Tuple.new
          end

          render "search"
        end
      end
    end

    def search_for(query : String) : Array({Result, Account?, Bool})
      case query
      when %r{\Ahttps://}
        id = URI.parse(query)
        account = Services::FetchRemoteAccount.new.call(id)
        i_follow = DB::AlreadyFollows[@current_user.try(&.id), account.id]
        results = [{account, nil, i_follow}] of ResultRow
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
        results = DB::Search[query, @current_user]
      end

      results
    end

    private def show(note : Note, author : Account, i_follow : Bool, response)
      render "search/note"
    end

    private def show(account : Account, _meh : Nil, i_follow : Bool, response)
      render "search/account"
    end

    private def show(result : Note, account : Nil, i_follow : Bool, response)
      puts "Missing author for note #{result.id.inspect}"
    end

    private def show(result : Account, account : Account, i_follow : Bool, response)
      raise InvalidResult.new("Received an account with another account? #{result.inspect} - #{account.inspect}")
    end

    alias Result = ::Note | ::Account
    alias ResultRow = {Result, Account?, Bool}

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

        r.get :handle do |handle|
          if account = DB::GetLocalAccountWithHandle[handle]
            post_count = DB::GetPostCountForAccount[handle]
            follower_count = DB::GetFollowerCountForAccount[handle]
            following_count = DB::GetFollowingCountForAccount[handle]
            followers = DB::GetFollowersForAccount[handle]
            following = DB::GetFollowingForAccount[handle]

            render "accounts/show"
          else
            render "not_found"
          end
        end
      end
    end
  end

  struct Admin
    include Route

    def initialize(@current_user : LocalAccount)
    end

    def call(context)
      route context do |r, response, session|
        r.root { render "admin/index" }

        r.on "accounts" do
          r.get do
            render "admin/accounts/index"
          end

          r.on "local" do
            r.get do
              accounts = DB::GetLocalAccounts.call
              render "admin/accounts/local"
            end

            r.get :handle do |handle|
              if account = DB::GetLocalAccountWithHandle[handle]
                pp account
                render "admin/accounts/local/show"
              else
                response.redirect "#{r.original_path}/.."
              end
            end
          end
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

        r.get "nodeinfo" do
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

# require "amqp-client"
# spawn do
#   AMQP::Client.start(ENV["AMQP_URL"]? || "amqp://guest:guest@localhost") do |amqp|
#     amqp.channel do |channel|
#       exchange = channel.exchange("activities", "fanout")

#       puts "Beginning message loop"
#       loop do
#         activity = Moku::ACTIVITY_QUEUE.receive
#         exchange.publish activity.to_json, ""
#       end
#     end
#   end
# end

server = HTTP::Server.new([
  HTTP::LogHandler.new,
  HTTP::CompressHandler.new,
  HTTP::MethodTranslation.new,
  HTTP::Session::RedisStore.new(
    key: "moku_session",
    redis: Redis::PooledClient.new(url: ENV["REDIS_URL"]?),
  ),
  Moku::App.new,
])

port = ENV.fetch("PORT", "5000").to_i
puts "Listening on #{port}..."
server.listen "0.0.0.0", port, reuse_port: true

module HTTP
  class MethodTranslation
    include HTTP::Handler

    def call(context)
      request = context.request
      if (request.method == "POST") && (body = request.body) && request.headers["Content-Type"]? == "application/x-www-form-urlencoded"
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

  module FormData
    def self.parse(request : ::Route::Request, &)
      parse request.@request do |part|
        yield part
      end
    end
  end
end
