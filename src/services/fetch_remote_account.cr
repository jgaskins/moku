require "json"
require "uri"

require "../database"
require "../activity_pub"

module Moku
  module Services
    struct FetchRemoteAccount
      def call(uri : URI) : ::Account
        puts "#{self.class}: #{uri.inspect}"
        response = ActivityPub.get(uri)
        if response.status.not_found?
          raise AccountNotFound.new("The URI #{uri.inspect} does not point to a valid ActivityPub account")
        end

        body = response.body
        json = JSON.parse(body)

        account = Account.new(
          id: URI.parse(json["id"].as_s),
          display_name: json["name"]?.try(&.as_s?) || json["preferredUsername"].as_s,
          handle: json["preferredUsername"].as_s,
          summary: json["summary"]?.try(&.as_s?) || "",
          manually_approves_followers: json["manuallyApprovesFollowers"]?.try(&.as_bool?) || false,
          discoverable: json["discoverable"]?.try(&.as_bool?) || false,
          followers_url: URI.parse(json["followers"].as_s),
          inbox_url: URI.parse(json["inbox"].as_s),
          shared_inbox: URI.parse((json["endpoints"]?.try { |endpoints| endpoints["sharedInbox"]? } || json["inbox"]).as_s),
          icon: json["icon"]?.try { |icon| URI.parse(icon["url"].as_s) },
          image: json["image"]?.try { |image| handle_image image },
        )

        DB::UpdatePerson[account]
        account
      rescue ex : KeyError | TypeCastError
        puts "JSON is not what we were expecting"
        pp json.not_nil!
        raise ex
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

    class AccountNotFound < ::Exception
    end
  end
end
