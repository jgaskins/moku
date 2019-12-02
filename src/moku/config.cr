require "amqp-client"
require "dotenv"
unless ENV["SKIP_DOTENV"]?
  Dotenv.load
end

module Moku
  VERSION = "0.1.0"

  # This needs to be the base URL at which this server is being run. For
  # example: https://my-instance.com
  SELF = URI.parse(ENV["SELF"])
  puts "Configured Moku server to run at #{SELF}"

  ACTIVITY_QUEUE = Channel(ActivityPub::Activity).new(64)
  PublicStreamURL = URI.parse("https://www.w3.org/ns/activitystreams#Public")
end
