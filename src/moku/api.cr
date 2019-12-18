require "./api/users"

require "../services/reify_partial_accounts"
require "../services/reify_partial_replyables"

struct Moku::API
  include Route

  def call(context)
    route context do |r, response, session|
      response.headers["Content-Type"] = "application/json"

      r.on "users" { Users.new.call context }
      r.on "inbox" { Inbox.new.call context }
      r.on ".well-known" { WellKnown.new.call context }
      r.on "v1" do
        # FIXME: Generalize this, make it configurable
        r.get "instance" do
          stats = DB::GetNodeInfo.call
          admin = DB::ListAdmins.call(limit: 1).first

          {
            uri: SELF.host,
            title: "Moku",
            short_description: "Flagship instance for Moku",
            description: "General Moku server",
            email: "jamie@zomglol.wtf",
            version: "0.1.0",
            urls: {
              # streaming_api: "wss://streaming.zomglol.wtf"
              primary: SELF,
            },
            stats: {
              user_count: stats.total_users,
              status_count: stats.local_posts,
              domain_count: 100,
            },
            thumbnail: "https://zomglol.wtf/packs/media/images/preview-9a17d32fc48369e8ccd910a75260e67d.jpg",
            languages: %w[en],
            registrations: stats.open_registrations,
            approval_required: stats.approval_required,
            contact_account: {
              id: admin.id,
              username: admin.handle,
              acct: admin.handle,
              display_name: admin.display_name,
              locked: false,
              bot: false,
              created_at: admin.created_at,
              note: admin.summary,
              url: admin.id,
              avatar: "https://uploads.zomglol.wtf/accounts/avatars/000/000/001/original/182a6238234cccbc.jpg",
              avatar_static: "https://uploads.zomglol.wtf/accounts/avatars/000/000/001/original/182a6238234cccbc.jpg",
              header: "https://uploads.zomglol.wtf/accounts/headers/000/000/001/original/a34f11ff5f057978.jpg",
              header_static: "https://uploads.zomglol.wtf/accounts/headers/000/000/001/original/a34f11ff5f057978.jpg",
              followers_count: 10,
              following_count: 12,
              statuses_count: 11,
              last_status_at: Time.utc,
              emojis: [] of String,
              fields: [
                # {
                #   name: "Pronouns",
                #   value: "he/him/his",
                #   verified_at: null
                # },
                # {
                #   name: "mastodon.social",
                #   value: "<span class=\"h-card\"><a href=\"https://mastodon.social/@jgaskins\" class=\"u-url mention\">@<span>jgaskins</span></a></span>",
                #   verified_at: null
                # }
              ] of String # FIXME: when we populate this make this a real type
            }
          }.to_json response
        end

        r.get "timelines/public" do
          # DB::GetNotesInStream is a streaming query, so we stream JSON generation
          JSON.build response do |json|
            json.array do
              DB::GetNotesInStream.call "https://www.w3.org/ns/activitystreams#Public", limit: 20 do |(note, author, attachments)|
                json.object do
                  json.field "id", note.id
                  json.field "created_at", note.created_at
                  # json.field "in_reply_to": ???
                  json.field "sensitive", note.sensitive?
                  json.field "spoiler_text", note.summary
                  json.field "visibility", "public"
                  json.field "uri", note.id
                  json.field "url", note.id
                  json.field "replies_count", 0
                  json.field "reblogs_count", 0
                  json.field "favourites_count", 0
                  json.field "content", note.content
                  json.field "reblog", nil
                  json.field "account" do
                    json.object do
                      json.field "id", author.id
                      json.field "username", author.handle
                      json.field "acct", author.handle
                      json.field "display_name", author.display_name
                      json.field "locked", false
                      json.field "bot", false
                      json.field "created_at", author.created_at
                      json.field "url", author.id
                      json.field "avatar", author.icon
                      json.field "avatar_static", author.icon
                      json.field "header", author.image
                      json.field "header_static", author.image
                      json.field "followers_count", 0
                      json.field "following_count", 0
                      json.field "statuses_count", 0
                      json.field "last_status_at", Time.utc
                      json.field "emojis" do
                        json.array {}
                      end
                      json.field "fields" do
                        json.array {}
                      end
                    end
                  end
                  json.field "media_attachments" do
                    json.array do
                      attachments.each do |attachment|
                        json.object do
                          json.field "type", attachment.type
                          json.field "url", attachment.url
                        end
                      end
                    end
                  end
                  json.field "mentions" do
                    json.array {}
                  end
                  json.field "mentions" do
                    json.array {}
                  end
                  json.field "tags" do
                    json.array {}
                  end
                  json.field "emojis" do
                    json.array {}
                  end
                  json.field "card" do
                    json.array {}
                  end
                  json.field "poll" do
                    json.array {}
                  end
                end
              end
            end
          end
        end
      end

      r.miss do
        response.status = HTTP::Status::NOT_FOUND
        { error: "Path not found" }.to_json response
      end
    end
  end

  struct Inbox
    include Route

    def call(context)
      route context do |r, response|
        r.root do
          r.post do
            if body = r.body
              body = body.gets_to_end if body.is_a? IO
              # pp r.headers
              # pp JSON.parse body
              activity = ActivityPub::Activity.from_json(body)

              if !authentication_required?(activity) || authentic?(r.headers, r.method, r.original_path)
                handle activity
              else
                response.status = HTTP::Status::UNAUTHORIZED
                { error: "Verification failed for #{r.headers["Signature"]?.try { |sig| sig.match(/keyId="([^\"])"/).try { |match| match[1] } }}" }.to_json response
                r.handled!
                return
              end
              # pp r.headers

              response.status = HTTP::Status::ACCEPTED
            else
              response.status = HTTP::Status::BAD_REQUEST
              return { error: "Missing body" }.to_json(response)
            end
          end
        end
      rescue ex
        pp ex
        pp ex.backtrace
        response.status = HTTP::Status::INTERNAL_SERVER_ERROR
        {
          error: "Internal server error",
        }.to_json response
        r.handled!
      end

      spawn Services::ReifyPartialAccounts.call
      # spawn Services::ReifyPartialReplyables.call
    end

    def handle(activity : ActivityPub::Activity)
      case activity.type
      when "Create", "Update"
        handle_create activity
      when "Delete"
        handle_delete activity
      when "Announce"
        handle_announce activity
      when "Undo"
        handle_undo activity
      else
        pp unhandled_activity: activity
      end
    end

    def handle_create(activity : ActivityPub::Activity)
      object = activity.object.as(ActivityPub::Object | ActivityPub::Activity)
      DB::PostNoteFromAccount[
        account_id: activity.actor.as(URI),
        id: object.id.not_nil!,
        type: object.type || "Note",
        content: object.content.as(String),
        created_at: object.published || Time.utc,
        summary: object.summary,
        sensitive: object.sensitive || false,
        url: object.url.not_nil!,
        in_reply_to: object.in_reply_to,
        attachments: (object.attachment || Array(ActivityPub::Activity).new).as(Array).map(&.as(ActivityPub::Activity)),
        to: object.to || %w[],
        cc: object.cc || %w[],
        poll_options: object.one_of,
      ]
    end

    def handle_delete(activity : ActivityPub::Activity)
      case object = activity.object
      when ActivityPub::Object, ActivityPub::Activity
        DB::DeleteNote[object.id.as(URI), activity.actor.as(URI)]
      when URI
        DB::DeleteObject[object]
      end
    end

    def handle_announce(activity : ActivityPub::Activity)
      json = HTTP::Client.get(activity.object.as(URI), headers: HTTP::Headers { "Accept" => "application/ld+json" }).body
      # puts json
      note = ActivityPub::Object.from_json(json)

      DB::BoostNote[actor_id: activity.actor.as(URI), note: note, announcement: activity]
    end

    def handle_undo(activity : ActivityPub::Activity)
      # pp activity
      object = activity.object.as(ActivityPub::Activity)

      case object.type
      when "Announce"
        DB::UndoBoost[
          actor_id: activity.actor.as(URI),
          note_id: object.object.as(URI),
        ]
      end
    end

    def authentication_required?(activity : ActivityPub::Activity) : Bool
      # When a remote site tells us they deleted a user, they'll send something
      # like this (cropped only to the parts we care about):
      #   {
      #     type: "Delete",
      #     object: "https://cool.website/users/omg",
      #     signature: {
      #       creator: "https://cool.website/users/omg#main-key",
      #     },
      #   }
      #
      # We can't verify the signature because the user is deleted, but we *can*
      # check that fetching the user's key returns an HTTP 410 GONE
      if activity.type == "Delete" && activity.object.is_a?(URI) && (signature = activity.signature) && (creator = signature.creator) && creator == URI.parse("#{activity.object}#main-key")
        response = HTTP::Client.get(
          creator,
          headers: HTTP::Headers { "accept" => "application/json" },
        )

        response.status != HTTP::Status::GONE
      else
        true
      end
    end

    def authentic?(headers, method, path) : Bool
      headers = headers.dup

      key_part, algorithm_part, headers_part, signature_part = headers["Signature"].split(',')
      if (match = key_part.match(/keyId="(.*)"/))
        key_url = URI.parse(match[1].gsub(/\#.*/, ""))
      end

      if (match = headers_part.match(/headers="(.*)"/)) && (header_keys = match[1].split(' '))
        headers["(request-target)"] = "#{method.downcase} #{path}"
        signable_string = header_keys
          .map { |key| "#{key}: #{headers[key]}" }
          .join('\n')
      end

      if (match = signature_part.match(/signature="(.*)"/))
        signature = String.new(Base64.decode(match[1]))
      end

      if key_url && signable_string && signature
        response = HTTP::Client.get(
          url: key_url,
          headers: HTTP::Headers {
            "Accept" => "application/json",
          },
        )

        if response.status == HTTP::Status::OK
          key = OpenSSL::RSA::KeyPair.new(
            public_key: JSON.parse(response.body).dig("publicKey", "publicKeyPem").as_s,
          )

          key.verify?(signature, signable_string)
        else
          false
        end
      else
        false
      end
    end

    class Exception < ::Exception
    end
    class NoActorID < Exception
    end
  end

  struct NodeInfo
    include Route

    def call(context)
      route context do |r, response|
        r.get "2.0" do
          node_info = DB::GetNodeInfo.call

          response.headers["Content-Type"] = "application/json"
          {
            "version": "2.0",
            "software": {
              "name": "moku",
              "version": "0.1.0"
            },
            "protocols": [
              "activitypub"
            ],
            "usage": {
              "users": {
                "total": node_info.total_users,
                "activeMonth": node_info.monthly_active_users,
                "activeHalfyear": node_info.half_yearly_active_users,
              },
              "localPosts": node_info.local_posts,
            },
            "openRegistrations": node_info.open_registrations,
          }.to_json response
        end

        r.miss do
          { error: "Unknown nodeinfo version" }.to_json response
        end
      end
    end
  end
end
