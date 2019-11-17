require "http"
require "json"
require "uuid"

require "dotenv"
Dotenv.load

require "../src/sign"
require "../src/database"

my_host = ARGV[0]
username = ARGV[1]

user_id = "https://#{my_host}/users/#{username}"

host = "zomglol.wtf"
body = {
  "@context": "https://www.w3.org/ns/activitystreams",
  id: "https://#{my_host}/activities/#{UUID.random}",
  type: "Follow",
  actor: user_id,
  object: "https://#{host}/users/jamie",
}.to_json

path = "/users/jamie/inbox"

request_target = "post #{path}"
host = "zomglol.wtf"
date = Time::Format::HTTP_DATE.format Time.utc
digest = "SHA-256=#{OpenSSL::Digest.new("SHA256").update(body).base64digest.strip}"
content_type = "application/activity+json"

priv, pub = pp(DB::NEO4J_POOL.connection(&.exec_cast("MATCH (:LocalAccount { handle: $handle })-[:HAS_KEY_PAIR]->(kp) RETURN kp.private_key, kp.public_key LIMIT 1", {handle: username}, {String, String}))).first

key = OpenSSL::RSA::KeyPair.new(
  public_key: pub,
  private_key: priv,
)
signable_string = pp({
  "(request-target)": request_target,
  host: host,
  date: date,
  digest: digest,
  "content-type": content_type,
}.map { |key, value| "#{key}: #{value}" }.join('\n'))
signature = key.sign(signable_string)
pp verified: key.verify?(signature, signable_string)
signature = Base64.strict_encode(signature)

headers = HTTP::Headers {
  "Accept" => "application/json",
  "Content-Type" => content_type,
  "Date" => date,
  "Digest" => digest,
  "Host" => host,
  "Signature" => {
    "keyId=#{"#{user_id}#main-key".inspect}",
    "algorithm=\"rsa-sha256\"",
    "headers=\"(request-target) host date digest content-type\"",
    "signature=#{signature.inspect}",
  }.join(','),
  "User-Agent" => "Follow.cr (lol/1.0.0; +https://#{my_host}/)",
}

pp headers: headers, body: JSON.parse(body)

response = HTTP::Client.post(
  url: URI.parse("https://#{host}#{path}"),
  headers: headers,
  body: body,
)

pp response.body


