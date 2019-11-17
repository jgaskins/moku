require "../spec_helper"
require "../factories/user"

require "../../src/moku/api/users"

describe Moku::API::Users do
  app = Moku::API::Users.new
  user = Factories::User.create

  it "returns information about the user" do
    response = build_context("GET", "/#{user.handle}") do |context|
      app.call(context)
    end

    response.status.should eq HTTP::Status::OK
    json = JSON.parse(response.body)
    json["preferredUsername"].should eq user.handle
    json["name"].should eq user.display_name
  end

  it "returns a Not Found response when the user does not exist" do
    response = build_context("GET", "/#{UUID.random.to_s}") do |context|
      app.call context
    end

    response.status.should eq HTTP::Status::NOT_FOUND
  end
end

describe Moku::API::Users::Inbox do
  user = Factories::User.create
  mq = Channel(ActivityPub::Activity).new
  app = Moku::API::Users::Inbox.new(user.handle, message_queue: mq)

  it "sends an Accept to the actor when receiving a Follow" do
    body = {
      type: "Follow",
      id: "https://example.com/follows/123",
      actor: "https://example.com/users/foo",
      object: user.id,
    }.to_json

    expected_activity = {
      id: "some_id",
      type: "Accept",
      actor: "https://example.com/users/foo",
      object: {
        id: "https://example.com/follows/123",
        type: "Follow",
        actor: "https://example.com/users/foo",
        object: user.id,
      }
    }

    accept_future = future { mq.receive }
    response = build_context("POST", "/", body: body) do |context|
      app.call context
    end
    accept = accept_future.get

    followers = DB::GetFollowersForAccount[user.handle]
    followers.map(&.id).includes?(URI.parse("https://example.com/users/foo")).should eq true

    response.status.should eq HTTP::Status::OK
    accept.type.should eq "Accept"
    accept.actor.should eq user.id
    accept.object.as(ActivityPub::Activity).tap do |object|
      object.id.should eq URI.parse("https://example.com/follows/123")
      object.actor.should eq URI.parse("https://example.com/users/foo")
      object.object.should eq user.id
    end
  end

  it "adds a post for a Create activity with a Note" do
    status_id = UUID.random.to_s
    body = {
      "@context": {
        "https://www.w3.org/ns/activitystreams",
        {
          ostatus: "http://ostatus.org#",
          atomUri: "ostatus:atomUri",
          inReplyToAtomUri: "ostatus:inReplyToAtomUri",
          conversation: "ostatus:conversation",
          sensitive: "as:sensitive",
          toot: "http://joinmastodon.org/ns#",
          votersCount: "toot:votersCount",
        }
      },
      id: "#{user.id}/statuses/#{status_id}/activity",
      type: "Create",
      actor: user.id,
      published: Time::Format::ISO_8601_DATE_TIME.format(Time.utc),
      to: ["https://www.w3.org/ns/activitystreams#Public"],
      cc: ["#{user.id}/followers"],
      object: {
        id: "#{user.id}/statuses/#{status_id}",
        type: "Note",
        summary: nil,
        inReplyTo: nil,
        published: Time::Format::ISO_8601_DATE_TIME.format(Time.utc),
        url: "https://zomglol.wtf/@jamie/#{status_id}",
        attributedTo: user.id,
        to: ["https://www.w3.org/ns/activitystreams#Public"],
        cc: ["#{user.id}/followers"],
        sensitive: false,
        atomUri: "#{user.id}/statuses/#{status_id}",
        inReplyToAtomUri: nil,
        conversation: "tag:zomglol.wtf,2019-11-03:objectId=6646:objectType=Conversation",
        content: "TEST #{UUID.random.to_s}",
        contentMap: {"en" => "<p>test</p>"},
      },
    }

    response = build_context("POST", "/", body: body.to_json) do |context|
      app.call context
    end

    response.status.should eq HTTP::Status::OK
    
    account, notes = DB::NotesForAccount[user.id]
    notes.any? { |p| p.content == body[:object][:content] }.should eq true
  end

  it "adds a post for an Announce activity with a Note" do

  end
end
