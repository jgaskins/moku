require "./spec_helper"

require "../src/database"

module DB
  describe CreateLocalAccount do
    it "creates an account with the specified properties" do
      prefix = "https://#{UUID.random}"
      handle = UUID.random.to_s
      id = URI.parse("#{prefix}/users/#{handle}")
      name = UUID.random.to_s

      account = CreateLocalAccount[
        id: id,
        handle: handle,
        name: name,
        email: "email#{UUID.random}@example.com",
        password: Crypto::Bcrypt::Password.create("password", cost: 4),
        public_key: "abc",
        private_key: "123",
        followers_url: URI.parse("#{id}/followers"),
        outbox_url: URI.parse("#{id}/outbox"),
        shared_inbox: URI.parse("#{prefix}/inbox"),
      ]

      account.id.should eq id
      account.handle.should eq handle
      account.display_name.should eq name
      account.password.verify("password").should eq true
    end
  end

  describe PostNoteFromAccount do
    it "" do

    end
  end
end
