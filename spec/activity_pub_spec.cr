require "./spec_helper"

require "../src/activity_pub"

request_metadata = {
  method: "POST",
  path: "/inbox",
  headers: HTTP::Headers{
    "Accept-Encoding" => "gzip",
    "Connection" => "close",
    "Content-Length" => "6244",
    "Content-Type" => "application/activity+json",
    "Date" => "Sat, 19 Oct 2019 22:32:46 GMT",
    "Digest" => "SHA-256=CrV0D/P2X4lOsy5/mH7wnTkcgBvLBSqSIIVoSpbN6wU=",
    "Host" => "jgaskins.wtf",
    "Signature" => "keyId=\"https://botsin.space/users/WowMachineRadio#main-key\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date digest content-type\",signature=\"r9UKGS7Pk+X/I0Bfg0KdHZPAMGCsiWDLAC/zBhPphX17/4Vaojqdqt20yOAocZ6+JNlcwR+cwKLkJAi9B4t8sN7VjhBNtTdUVLmlYaZc6EAhd7dn7G74O+bV+PVTccPQmHiBKgdmCdAQA9mvVZufVLGlmlNcP6NbsDBqi6/lg6jKOESBflKptW2rLzgPiha6pik+7m7z6rzTIk2dRcy8QGi2k78yP8Mf9YC1rVkebJTBqYG39eDxuq4YLJiOv0qxpZPH7KlhaoMpuRwixRw3xc/sEat9OOdXE3GHMt3Nyibg0kGK0zUdZKCXMpZp4GerVUx8xyYiqTzKiwIAvLZr1w==\"",
    "User-Agent" => "http.rb/3.3.0 (Mastodon/3.0.0; +https://botsin.space/)",
    "X-Forwarded-For" => "159.89.230.222",
    "X-Forwarded-Port" => "443",
    "X-Forwarded-Proto" => "https",
  },
  query: HTTP::Params.new,
}
create_activity_json = {
  "@context" => [
    "https://www.w3.org/ns/activitystreams",
    {
      "ostatus" => "http://ostatus.org#",
      "atomUri" => "ostatus:atomUri",
      "inReplyToAtomUri" => "ostatus:inReplyToAtomUri",
      "conversation" => "ostatus:conversation",
      "sensitive" => "as:sensitive",
      "toot" => "http://joinmastodon.org/ns#",
      "votersCount" => "toot:votersCount",
      "blurhash" => "toot:blurhash",
      "focalPoint" => {"@container" => "@list", "@id" => "toot:focalPoint"},
      "Hashtag" => "as:Hashtag",
    }
  ],
  "id" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727/activity",
  "type" => "Create",
  "actor" => "https://botsin.space/users/WowMachineRadio",
  "published" => "2019-10-19T22:24:20Z",
  "to" => ["https://www.w3.org/ns/activitystreams#Public"],
  "cc" => ["https://botsin.space/users/WowMachineRadio/followers"],
  "object" => {
    "id" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727",
    "type" => "Note",
    "summary" => nil,
    "inReplyTo" => nil,
    "published" => "2019-10-19T22:24:20Z",
    "url" => "https://botsin.space/@WowMachineRadio/102991387691454727",
    "attributedTo" => "https://botsin.space/users/WowMachineRadio",
    "to" => ["https://www.w3.org/ns/activitystreams#Public"],
    "cc" => ["https://botsin.space/users/WowMachineRadio/followers"],
    "sensitive" => false,
    "atomUri" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727",
    "inReplyToAtomUri" => nil,
    "conversation" => "tag:botsin.space,2019-10-19:objectId=21415465:objectType=Conversation",
    "content" => "<p>You Never Know What Will Play Next!</p><p>Grandmaster Flash-♫Kid Named Flash♫<br />Ba-Dop-Boom-Bang<br /><a href=\"http://v.ht/RaDiO\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/RaDiO</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/Zd5M\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/Zd5M</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/Yfotf\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/Yfotf</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/nJpm\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/nJpm</span><span class=\"invisible\"></span></a></p><p><a href=\"https://botsin.space/tags/AroundTheWorld\" class=\"mention hashtag\" rel=\"tag\">#<span>AroundTheWorld</span></a> <a href=\"https://botsin.space/tags/StreamingLive\" class=\"mention hashtag\" rel=\"tag\">#<span>StreamingLive</span></a> <a href=\"https://botsin.space/tags/Uncensored\" class=\"mention hashtag\" rel=\"tag\">#<span>Uncensored</span></a></p>",
    "contentMap" => {
      "en" => "<p>You Never Know What Will Play Next!</p><p>Grandmaster Flash-♫Kid Named Flash♫<br />Ba-Dop-Boom-Bang<br /><a href=\"http://v.ht/RaDiO\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/RaDiO</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/Zd5M\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/Zd5M</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/Yfotf\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/Yfotf</span><span class=\"invisible\"></span></a> <a href=\"http://v.ht/nJpm\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">http://</span><span class=\"\">v.ht/nJpm</span><span class=\"invisible\"></span></a></p><p><a href=\"https://botsin.space/tags/AroundTheWorld\" class=\"mention hashtag\" rel=\"tag\">#<span>AroundTheWorld</span></a> <a href=\"https://botsin.space/tags/StreamingLive\" class=\"mention hashtag\" rel=\"tag\">#<span>StreamingLive</span></a> <a href=\"https://botsin.space/tags/Uncensored\" class=\"mention hashtag\" rel=\"tag\">#<span>Uncensored</span></a></p>",
    },
    "attachment" => [
      {
        "type" => "Document",
        "mediaType" => "image/jpeg",
        "url" => "https://files.botsin.space/media_attachments/files/004/163/640/original/667bf8dbf2b5a91c.jpg",
        "name" => nil,
        "blurhash" => "UQD]Vf$*D%ax_4RjM{t7RlofWBNG00R*xuof",
      }
    ],
    "tag" => [
      {
        "type" => "Hashtag",
        "href" => "https://botsin.space/tags/uncensored",
        "name" => "#uncensored",
      },
      {
        "type" => "Hashtag",
        "href" => "https://botsin.space/tags/streaminglive",
        "name" => "#streaminglive",
      },
      {
        "type" => "Hashtag",
        "href" => "https://botsin.space/tags/aroundtheworld",
        "name" => "#aroundtheworld",
      }
    ],
    "replies" => {
      "id" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727/replies",
      "type" => "Collection",
      "first" => {
        "type" => "CollectionPage",
        "next" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727/replies?only_other_accounts=true&page=true",
        "partOf" => "https://botsin.space/users/WowMachineRadio/statuses/102991387691454727/replies",
        "items" => [] of String,
      }
    }
  },
  "signature" => {
    "type" => "RsaSignature2017",
    "creator" => "https://botsin.space/users/WowMachineRadio#main-key",
    "created" => "2019-10-19T22:24:20Z",
    "signatureValue" => "zsBYIsY2aqVdo8ooTBlvMmK/KIgosqSAM0Nf1xyMsMdOiFezmbYn/a7/a4pymoI1C9qw0U1+RHqwOUvuA4bP++iLKHdoPJkPRqvoPU1iBfT+yJagJO5m9PiEGVeDDi2FAJIu6qFdEBZ5yffrQ5eV1sgp1bK4TiabtMaK1BcYnYI6eu/1nIzurTIFyfI86CuNIasMzYWAXdOKbXHrxXbo27skWay9niMqFhhde5ny8Qu8TZgmryR2sTsuRSbPhWhfRk9zMSJEkKQd+ZC7x6+N1bSMjlRSRaUQbmr8gJAx+UryznWeb2Zj+Y6RaUGeM0VfjiF1JfqCWUL554ma5cWVNA==",
  },
}.to_json

follow_activity_json = {
  "@context" => "https://www.w3.org/ns/activitystreams",
  "id" => "https://mastodon.social/b6b466f9-87b3-46c9-a188-d178f0e35fce",
  "type" => "Follow",
  "actor" => "https://mastodon.social/users/jgaskins",
  "object" => "https://jgaskins.wtf/users/jamie",
}.to_json

undo_activity_json = {
  "@context" => "https://www.w3.org/ns/activitystreams",
  "id" => "https://mastodon.social/users/jgaskins#follows/6862521/undo",
  "type" => "Undo",
  "actor" => "https://mastodon.social/users/jgaskins",
  "object" => {
    "id" => "https://mastodon.social/a714f7fb-8687-4313-b324-46c5db474872",
    "type" => "Follow",
    "actor" => "https://mastodon.social/users/jgaskins",
    "object" => "https://jgaskins.wtf/users/jamie",
  }
}.to_json

# describe ActivityPub do
#   it "parses a Create activity" do
#     activity = ActivityPub.parse(create_activity_json).as(ActivityPub::Create)

#     activity.id.should eq URI.parse("https://botsin.space/users/WowMachineRadio/statuses/102991387691454727/activity")
#     activity.actor.should eq URI.parse("https://botsin.space/users/WowMachineRadio")
#     activity.reify_actor.id.should eq URI.parse("https://botsin.space/users/WowMachineRadio")
#   end

#   it "parses a Follow activity" do
#     activity = ActivityPub.parse(follow_activity_json).as(ActivityPub::Follow)

#     activity.actor.should eq URI.parse("https://mastodon.social/users/jgaskins")
#     activity.object.should eq URI.parse("https://jgaskins.wtf/users/jamie")
#   end
# end
