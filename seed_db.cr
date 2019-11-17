require "dotenv"
Dotenv.load

require "./src/moku/config"
require "./src/database"
require "./src/sign"
require "./src/activity_pub"

admin = pp Account.new(
  id: URI.parse("#{Moku::SELF}/users/admin"),
  handle: "admin",
  display_name: "Admin",
  shared_inbox: URI.parse("#{Moku::SELF}/inbox"),
  followers_url: URI.parse("#{Moku::SELF}/users/admin/followers"),
  summary: "Administrator of this Moku instance",
  manually_approves_followers: false,
  discoverable: true,
)

key = OpenSSL::RSA::KeyPair.generate

DB::NEO4J_POOL.connection do |connection|
  connection.execute <<-CYPHER,
    MERGE (admin:Admin:Moderator:LocalAccount:Account:Person {
      handle: $admin_handle
    })
    ON CREATE SET admin.created_at = datetime()

    WITH admin
    SET admin.id = $admin_id,
      admin.display_name = $admin_name,
      admin.discoverable = $admin_discoverable,
      admin.followers_url = $admin_followers_url,
      admin.icon = $admin_icon_url,
      admin.image = $admin_image_url,
      admin.manually_approves_followers = $admin_manually_approves_followers,
      admin.shared_inbox = $admin_shared_inbox,
      admin.summary = $admin_summary,
      admin.updated_at = datetime()

    MERGE (admin)-[:HAS_KEY_PAIR]->(key_pair:KeyPair)
    ON CREATE SET
      key_pair.public_key = $public_key_pem,
      key_pair.private_key = $private_key_pem
  CYPHER
    admin_id: admin.id.to_s,
    admin_handle: admin.handle,
    admin_name: admin.display_name,
    admin_summary: admin.summary,
    admin_shared_inbox: admin.shared_inbox.to_s,
    admin_followers_url: admin.followers_url.to_s,
    admin_manually_approves_followers: admin.manually_approves_followers?,
    admin_discoverable: admin.discoverable?,
    admin_icon_url: admin.icon ? admin.icon.to_s : nil,
    admin_image_url: admin.image ? admin.image.to_s : nil,
    public_key_pem: key.public_key_pem,
    private_key_pem: key.private_key_pem
end
