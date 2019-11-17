require "./route"
require "./sign"

module Moku
  struct SignUp
    include Route

    def call(context)
      route context do |r, response, session|
        r.get { render "signup" }
        r.post do
          if body = r.body
            params = HTTP::Params.parse(body.gets_to_end)
            handle = params["handle"]
            id = URI.parse("#{SELF}/users/#{handle}")
            keypair = OpenSSL::RSA::KeyPair.generate

            DB::CreateLocalAccount[
              id: id,
              handle: handle,
              name: params["display_name"],
              email: params["email"],
              password: Crypto::Bcrypt::Password.create(params["password"]),
              public_key: keypair.public_key_pem,
              private_key: keypair.private_key_pem,
            ]
            session["user_id"] = id.to_s

            response.redirect "/home"
          else
            response.status = HTTP::Status::BAD_REQUEST
            response << "<h2>Must supply request body</h2>"
          end
        end
      end
    end
  end
end
