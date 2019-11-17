require "./api/users"

require "../services/reify_partial_accounts"

struct Moku::API
  include Route

  def call(context)
    route context do |r, response, session|
      response.headers["Content-Type"] = "application/json"

      if authentication_required?(r) && !authentic?(r.headers, r.method, r.path)
        response.status = HTTP::Status::UNAUTHORIZED
        { error: "Verification failed for #{r.headers["Signature"]?.try { |sig| sig.match(/keyId="([^\"])"/).try { |match| match[1] } }}" }.to_json response
        return
      end
      # pp r.headers

      r.on "users" { Users.new.call context }
      r.on "inbox" { Inbox.new.call context }
      r.on ".well-known" { WellKnown.new.call context }
      r.miss do
        response.status = HTTP::Status::NOT_FOUND
        { error: "Path not found" }.to_json response
      end
    end
  end

  def authentication_required?(request)
    request.method == "POST"
  end

  def authentic?(headers, method, path) : Bool
    headers = headers.dup

    key_part, algorithm_part, headers_part, signature_part = headers["Signature"].split(',')
    if (match = key_part.match(/keyId="(.*)"/))
      key_url = URI.parse(match[1])
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

      key = OpenSSL::RSA::KeyPair.new(
        public_key: JSON.parse(response.body).dig("publicKey", "publicKeyPem").as_s,
      )

      key.verify?(signature, signable_string)
    else
      false
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
              handle ActivityPub::Activity.from_json(body)
              response.status = HTTP::Status::ACCEPTED
            else
              response.status = HTTP::Status::BAD_REQUEST
              return { error: "Missing body" }.to_json(response)
            end
          end
        end
      rescue ex
        pp ex
        response.status = HTTP::Status::INTERNAL_SERVER_ERROR
        {
          error: "Internal server error",
        }.to_json response
      end

      spawn Services::ReifyPartialAccounts.call
    end

    def handle(activity : ActivityPub::Activity)
      case activity.type
      when "Create"
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
        content: object.content.as(String),
        created_at: object.published || Time.utc,
        summary: object.summary,
        url: object.url.not_nil!,
        attachments: (object.attachment || Array(ActivityPub::Activity).new).as(Array).map(&.as(ActivityPub::Activity)),
        to: object.to || %w[],
        cc: object.cc || %w[],
      ]
    end

    def handle_delete(activity : ActivityPub::Activity)
      note_id = activity
        .object.as(ActivityPub::Object | ActivityPub::Activity)
        .id.as(URI)

      DB::DeleteNote[note_id, activity.actor.as(URI)]
    end

    def handle_announce(activity : ActivityPub::Activity)
      json = HTTP::Client.get(activity.object.as(URI), headers: HTTP::Headers { "Accept" => "application/json" }).body
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

    class Exception < ::Exception
    end
    class NoActorID < Exception
    end
  end

  struct NodeInfo
    include Route

    def call(context)
      route context do |r, response|
        r.on "2.0" do
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
