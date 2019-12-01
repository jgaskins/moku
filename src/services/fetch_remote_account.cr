require "http"
require "json"
require "uri"

require "../database"

module Moku
  module Services
    struct FetchRemoteAccount
      def call(uri : URI) : ::Account
        puts "#{self.class}: #{uri.inspect}"
        body = HTTP::Client.get(uri, headers: HTTP::Headers { "Accept" => "application/ld+json" }).body
        json = JSON.parse(body)

        account = Account.new(
          id: URI.parse(json["id"].as_s),
          display_name: json["name"].as_s,
          handle: json["preferredUsername"].as_s,
          summary: json["summary"]?.try(&.as_s) || "",
          manually_approves_followers: json["manuallyApprovesFollowers"]?.try(&.as_bool?) || false,
          discoverable: json["discoverable"]?.try(&.as_bool?) || false,
          followers_url: URI.parse(json["followers"].as_s),
          inbox_url: URI.parse(json["inbox"].as_s),
          shared_inbox: URI.parse(json.dig("endpoints", "sharedInbox").as_s),
          icon: json["icon"]?.try { |icon| URI.parse(icon["url"].as_s) },
          image: json["image"]?.try { |image| handle_image image },
        )

        DB::UpdatePerson[account]
        account
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
