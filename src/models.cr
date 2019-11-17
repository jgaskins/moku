require "neo4j"
require "crypto/bcrypt/password"

module PropertyConversion
  module URI
    def self.deserialize(string : Neo4j::Value)
      ::URI.parse string.as(String)
    end
  end

  module Bcrypt
    def self.deserialize(string)
      Crypto::Bcrypt::Password.new(string.as(String))
    end
  end
end

struct Account
  Neo4j.map_node(
    id: { type: URI, converter: PropertyConversion::URI },
    handle: String,
    display_name: String,
    summary: String,
    manually_approves_followers: Bool,
    discoverable: Bool,
    followers_url: { type: URI, converter: PropertyConversion::URI },
    inbox_url: { type: URI?, converter: PropertyConversion::URI, default: nil },
    shared_inbox: { type: URI, converter: PropertyConversion::URI },
    icon: { type: URI?, converter: PropertyConversion::URI, default: nil },
    image: { type: URI?, converter: PropertyConversion::URI, default: nil },
  )

  property? manually_approves_followers = false
  property? discoverable = true

  def initialize(
    @id,
    @handle,
    @display_name,
    @shared_inbox,
    @summary = "",
    @followers_url = URI.parse("#{id}/followers"),
    @inbox_url = URI.parse("#{id}/inbox"),
    @icon = nil,
    @image = nil,
    @manually_approves_followers = false,
    @discoverable = true,
  )
    @node_id = -1
    @node_labels = %w[]
  end
end

struct LocalAccount
  Neo4j.map_node(
    id: { type: URI, converter: PropertyConversion::URI },
    handle: String,
    display_name: String,
    password: {type: Crypto::Bcrypt::Password, converter: PropertyConversion::Bcrypt},
    summary: String,
    manually_approves_followers: Bool,
    discoverable: Bool,
    followers_url: { type: URI, converter: PropertyConversion::URI },
    shared_inbox: { type: URI, converter: PropertyConversion::URI },
    icon: { type: URI?, converter: PropertyConversion::URI, default: nil },
    image: { type: URI?, converter: PropertyConversion::URI, default: nil },
  )
end

struct PartialAccount
  Neo4j.map_node(
    id: { type: URI, converter: PropertyConversion::URI },
    created_at: Time,
    updated_at: Time,
  )
end

struct Attachment
  Neo4j.map_node(
    type: String,
    name: String?,
    value: String?,
    url: String?,
    media_type: String?,
  )
end

struct Activity
  Neo4j.map_node(
    id: { type: URI, converter: PropertyConversion::URI },
    type: String,
    to: Array(String),
    cc: Array(String),
    created_at: Time,
  )
end

struct Note
  Neo4j.map_node(
    id: { type: URI, converter: PropertyConversion::URI },
    type: String,
    summary: String,
    # in_reply_to: { type: URI?, converter: PropertyConversion::URI },
    created_at: Time,
    url: { type: URI, converter: PropertyConversion::URI },
    to: Array(String),
    cc: Array(String),
    sensitive: Bool,
    content: String,
  )

  property in_reply_to : URI? = nil
end
