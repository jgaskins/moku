require "http"
require "json"
require "uri"

require "../database"

module Moku
  module Services
    struct FetchRemoteAccount
      def call(uri : URI) : ::Account
        json = JSON.parse(HTTP::Client.get(uri, headers: HTTP::Headers { "Accept" => "application/json" }).body)

        account = Account.new(
          id: URI.parse(json["id"].as_s),
          display_name: json["name"].as_s,
          handle: json["preferredUsername"].as_s,
          summary: json["summary"].as_s,
          manually_approves_followers: json["manuallyApprovesFollowers"].as_bool? || false,
          discoverable: json["discoverable"].as_bool? || false,
          followers_url: URI.parse(json["followers"].as_s),
          inbox_url: URI.parse(json["inbox"].as_s),
          shared_inbox: URI.parse(json.dig("endpoints", "sharedInbox").as_s),
          icon: json["icon"]?.try { |icon| URI.parse(icon["url"].as_s) },
          image: json["image"]?.try { |image| URI.parse(image["url"].as_s) },
        )

        DB::UpdatePerson[account]
        account
      end
    end
  end
end
