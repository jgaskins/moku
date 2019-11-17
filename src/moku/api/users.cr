require "../../database"
require "../../route"
require "../../activity_pub"
require "../config"

require "../../services/fetch_remote_account"

module Moku; struct API; struct Users
  include Route

  def call(context)
    route context do |r, response, session|
      r.on :handle do |handle|
        r.on "followers" { Followers.new(handle).call context }
        r.on "following" { Following.new(handle).call context }
        r.on "outbox" { Outbox.new(handle).call context }
        r.on "inbox" { Inbox.new(handle).call context }
        r.on "notes" { Notes.new(handle).call context }

        r.is do
          user, public_key, attachments = DB::GetAccountWithPublicKeyAndAttachments[handle]
          {
            "@context": {
              "https://www.w3.org/ns/activitystreams",
              "https://w3id.org/security/v1",
              # {
              #   "manuallyApprovesFollowers": "as:manuallyApprovesFollowers",
              #   "featured": {
              #     "@id": "toot:featured",
              #     "@type": "@id"
              #   },
              #   "alsoKnownAs": {
              #     "@id": "as:alsoKnownAs",
              #     "@type": "@id"
              #   },
              #   "movedTo": {
              #     "@id": "as:movedTo",
              #     "@type": "@id"
              #   },
              #   "schema": "http://schema.org#",
              #   "PropertyValue": "schema:PropertyValue",
              #   "value": "schema:value",
              #   "IdentityProof": "toot:IdentityProof",
              #   "discoverable": "toot:discoverable",
              #   "focalPoint": {
              #     "@container": "@list",
              #     "@id": "toot:focalPoint"
              #   }
              # }
            },
            id: "#{Moku::SELF}/users/#{handle}",
            type: "Person",
            following: "#{Moku::SELF}/users/#{handle}/following",
            followers: "#{Moku::SELF}/users/#{handle}/followers",
            inbox: "#{Moku::SELF}/users/#{handle}/inbox",
            outbox: "#{Moku::SELF}/users/#{handle}/outbox",
            # "featured": "#{Moku::SELF}/users/#{handle}/collections/featured",
            preferredUsername: user.handle,
            name: user.display_name,
            summary: user.summary,
            url: "#{Moku::SELF}/users/#{user.handle}",
            manuallyApprovesFollowers: user.manually_approves_followers?,
            discoverable: user.discoverable?,
            publicKey: {
              id: "#{Moku::SELF}/users/#{handle}#main-key",
              owner: "#{Moku::SELF}/users/#{handle}",
              publicKeyPem: public_key,
            },
            tag: [] of ActivityPub::Tag,
            attachment: attachments.map { |attachment|
              {
                type: attachment.type,
                name: attachment.name,
                value: attachment.value,
              }
            },
            endpoints: {
              sharedInbox: "#{Moku::SELF}/inbox"
            },
            # "icon": {
            #   "type": "Image",
            #   "mediaType": "image/png",
            #   "url": "https://files.mastodon.social/accounts/avatars/000/028/769/original/d7ca3d2190f3acb7.png"
            # }
          }.to_json response
        end
      rescue DB::Query::NotFound
        response.status = HTTP::Status::NOT_FOUND
        {error: "No local account found with handle #{handle.inspect}"}.to_json response
      end
    end
  end

  struct Inbox
    include Route

    def initialize(@handle : String, @message_queue = Moku::ACTIVITY_QUEUE)
    end

    def call(context)
      route context do |r, response|
        r.root do
          r.post do
            if body = r.body
              body = body.gets_to_end if body.is_a? IO
              # pp r.headers
              pp JSON.parse body
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
      when "Accept"
        follow activity.actor
      when "Follow"
        handle_follow_request activity
      when "Create"
        handle_create activity
      when "Undo"
        handle_undo activity
      else
        pp activity
      end
    end

    def follow(actor : ActivityPub::Object | ActivityPub::Activity)
      follow actor.id
    end

    def follow(id : URI)
      account = Services::FetchRemoteAccount.new.call id
      DB::ConfirmFollowUser[@handle, followee_id: id, followers_stream: account.followers_url]
    end

    def follow(id : Nil)
      raise NoActorID.new("Actor has no id")
    end

    def handle_follow_request(activity : ActivityPub::Activity)
      spawn do
        DB::AcceptFollowRequest[activity.actor.as(URI), activity.object.as(URI)]
        accept = ActivityPub::Activity.new(
          id: URI.parse("#{SELF}/follows/#{UUID.random}"),
          actor: activity.object,
          type: "Accept",
          object: activity,
        )
        account = Services::FetchRemoteAccount.new.call activity.actor.as(URI)
        key_pair = DB::GetKeyPairForAccount[activity.object.as(URI)]
        Services::SendActivity[accept, account.shared_inbox, key_pair]
      end
    end

    def handle_create(activity : ActivityPub::Activity)
      # pp activity
      object = activity.object.as(ActivityPub::Object | ActivityPub::Activity)
      DB::PostNoteFromAccount[
        account_id: activity.actor.as(URI),
        id: object.id.not_nil!,
        content: object.content.as(String),
        created_at: object.published || Time.utc,
        summary: object.summary,
        url: object.url.not_nil!,
        to: object.to || %w[],
        cc: object.cc || %w[],
      ]
    end

    def handle_undo(activity : ActivityPub::Activity)
      case (undone_activity = activity.object.as(ActivityPub::Activity)).type
      when "Follow"
        unfollow undone_activity
      end
    end

    def unfollow(activity : ActivityPub::Activity)
      actor = activity.actor.as(URI)
      account = activity.object.as(URI)

      DB::Unfollow[follower_id: actor, followee_id: account]
    end

    class Exception < ::Exception
    end
    class NoActorID < Exception
    end
  end

  struct Followers
    include Route

    def initialize(@handle : String)
    end

    def call(context)
      route context do |r, response|
        r.on "page" do
          r.on :page do |page|
            followers = DB::GetFollowersForAccount[@handle]

            {
              "@context": "https://www.w3.org/ns/activitystreams",
              id: "#{SELF}/users/jamie/followers/page/1",
              type: "OrderedCollectionPage",
              totalItems: followers.size,
              partOf: "#{SELF}/users/jamie/followers",
              orderedItems: followers.map(&.id),
            }.to_json response
          end
        end

        r.root do
          follower_count = DB::GetFollowerCountForAccount[@handle]

          {
            "@context": "https://www.w3.org/ns/activitystreams",
            "id": "#{SELF}/users/#{@handle}/followers",
            "type": "OrderedCollection",
            "totalItems": follower_count,
            "first": "#{SELF}/users/#{@handle}/followers/page/1"
          }.to_json response
        end
      end
    end
  end

  struct Following
    include Route

    def initialize(@handle : String)
    end

    def call(context)
      route context do |r, response|
        r.on "page" do
          r.on :page do |page|
            following = DB::GetFollowingForAccount[@handle]

            {
              "@context": "https://www.w3.org/ns/activitystreams",
              id: "#{SELF}/users/jamie/following/page/1",
              type: "OrderedCollectionPage",
              totalItems: following.size,
              partOf: "#{SELF}/users/jamie/following",
              orderedItems: following.map(&.id),
            }.to_json response
          end
        end

        r.root do
          following_count = DB::GetFollowingCountForAccount[@handle]

          {
            "@context": "https://www.w3.org/ns/activitystreams",
            "id": "#{SELF}/users/#{@handle}/following",
            "type": "OrderedCollection",
            "totalItems": following_count,
            "first": "#{SELF}/users/#{@handle}/following/page/1"
          }.to_json response
        end
      end
    end
  end

  struct Outbox
    include Route

    def initialize(@handle : String)
    end

    def call(context)
      route context do |r, response|
        r.root do
          r.params "latest" do |(latest)|
            if latest.empty?
              latest_timestamp = Time.utc
            else
              latest_timestamp = Time::UNIX_EPOCH + latest.to_f.seconds
            end

            items = DB::OutboxCollectionItemsForAccount[@handle, older_than: latest_timestamp]

            {
              "@context": [
                "https://www.w3.org/ns/activitystreams",
                # {
                #   "ostatus": "http://ostatus.org#",
                #   "atomUri": "ostatus:atomUri",
                #   "inReplyToAtomUri": "ostatus:inReplyToAtomUri",
                #   "conversation": "ostatus:conversation",
                #   "sensitive": "as:sensitive",
                #   "toot": "http://joinmastodon.org/ns#",
                #   "votersCount": "toot:votersCount"
                # }
              ],
              id: "#{SELF}/users/#{@handle}/outbox?latest=#{latest}",
              type: "OrderedCollectionPage",
              prev: items.empty? ? nil : "#{SELF}/users/jamie/outbox?latest=#{items.last.created_at.to_unix_f}",
              partOf: "#{SELF}/users/jamie/outbox",
              orderedItems: items.map { |object|
                ActivityPub::Activity.new(
                  id: URI.parse("#{object.id}/activity"),
                  type: "Create",
                  actor: URI.parse("#{SELF}/users/#{@handle}"),
                  to: object.to,
                  cc: object.cc,
                  object: object ? ActivityPub::Object.new(
                    id: object.id,
                    type: object.type,
                    summary: object.summary,
                    in_reply_to: object.in_reply_to,
                    published: object.created_at,
                    url: object.url,
                    to: object.to,
                    cc: object.cc,
                    sensitive: object.sensitive || false,
                    content: object.content,
                    # content_map: object.content_map,
                    attachment: Array(ActivityPub::Value).new,
                    tag: Array(ActivityPub::Object).new,
                    replies: ActivityPub::Collection(ActivityPub::Object).new(
                      id: URI.parse("#{object.id}/replies"),
                      type: "Collection",
                      first: URI.parse("#{object.id}/replies/all"),
                    ),
                  ) : nil,
                )
              }
            }.to_json response
          end

          r.get do
            item_count = DB::OutboxCollectionCountForAccount[@handle]

            {
              "@context": "https://www.w3.org/ns/activitystreams",
              id: "#{SELF}/users/jamie/outbox",
              type: "OrderedCollection",
              totalItems: item_count,
              first: "#{SELF}/users/jamie/outbox?latest=",
              last: "#{SELF}/users/jamie/outbox?latest=0"
            }.to_json response
          end
        end
      end
    end
  end

  struct Notes
    include Route

    def initialize(@handle : String)
    end

    def call(context)
      route context do |r, response|
        r.on :id do |id|
          pp r.original_path
        end
      end
    end
  end
end
end
end
