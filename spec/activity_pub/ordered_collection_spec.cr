require "../spec_helper"

require "../../src/activity_pub"
require "http"

module ActivityPub
  describe OrderedCollection do
    it "does a thing" do
      response = ActivityPub.get("https://zomglol.wtf/users/jamie/outbox")

      collection = pp OrderedCollection(Activity).from_json response.body
      pp collection.to_a
    end
  end
end
