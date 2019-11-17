require "../../src/database"
require "../../src/sign"

module Factories
  module User
    extend self

    def create(handle = generate_handle, key = generate_key)
      user = DB::CreateLocalAccount[
        handle: handle,
        name: handle,
        id: URI.parse("#{Moku::SELF}/users/#{handle}"),
        public_key: key.public_key_pem,
        private_key: key.private_key_pem,
      ]
    end

    def generate_handle
      UUID.random.to_s
    end

    def generate_key
      OpenSSL::RSA::KeyPair.generate(128)
    end
  end
end
