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

  AWS_ACCESS_KEY_ID = ENV["AWS_ACCESS_KEY_ID"]
  AWS_SECRET_ACCESS_KEY = ENV["AWS_SECRET_ACCESS_KEY"]
  AWS_REGION = ENV["AWS_REGION"]

  S3_ENDPOINT = ENV["S3_ENDPOINT"]
  S3_BUCKET = ENV["S3_BUCKET"]
  S3_CDN_URL = ENV["S3_CDN_URL"]
end
