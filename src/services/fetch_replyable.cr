require "json"
require "uri"

require "../database"
require "../activity_pub"

module Moku
  module Services
    struct FetchReplyable
      def call(uri : URI)
        puts "#{self.class}: #{uri.inspect}"
        json = ActivityPub.get(uri).body
        object = ActivityPub::Object.from_json(json)

        if object.id
          DB::PostNoteFromAccount[
            account_id: object.attributed_to.as(URI),
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
      end

      def handle_image(image : JSON::Any)
        if image.as_s?
          handle_image image.as_s
        elsif image.as_a?
          handle_image image.as_a.first
        elsif image.as_h?
          handle_image image.as_h
        end
      end

      def handle_image(image : Hash(String, JSON::Any))
        handle_image image["url"]
      end

      def handle_image(image : String)
        URI.parse(image)
      end
    end
  end
end
