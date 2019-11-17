require "openssl"

lib LibCrypto
  struct BigNum
    d : Pointer(ULong)
    top : Int
    dmax : Int
    neg : Int
    flags : Int
  end

  struct RSA
    n : BigNum*
    e : BigNum*
    d : BigNum*
    p : BigNum*
    q : BigNum*
    dmp1 : BigNum*
    dmq1 : BigNum*
    iqmp : BigNum*
  end

  fun rsa_new = RSA_new : RSA*
  fun rsa_free = RSA_free(rsa : RSA*) : Void
  fun rsa_size = RSA_size(rsa : RSA*) : Int
  fun rsa_public_key_dup = RSAPublicKey_dup(rsa : RSA*) : RSA*
  fun rsa_private_key_dup = RSAPrivateKey_dup(rsa : RSA*) : RSA*
  fun rsa_public_encrypt = RSA_public_encrypt(flen : Int, from : Char*, to : Char*, rsa : RSA*, padding : Int) : Int
  fun rsa_private_decrypt = RSA_private_decrypt(flen : Int, from : Char*, to : Char*, rsa : RSA*, padding : Int) : Int
  fun rsa_private_encrypt = RSA_private_encrypt(flen : Int, from : Char*, to : Char*, rsa : RSA*, padding : Int) : Int
  fun rsa_public_decrypt = RSA_public_decrypt(flen : Int, from : Char*, to : Char*, rsa : RSA*, padding : Int) : Int
  fun rsa_sign = RSA_sign(type : Int, m : Char*, m_length : Int, sigret : Char*, siglen : Int*, rsa : RSA*) : Int
  fun rsa_verify = RSA_verify(type : Int, m : Char*, m_length : Int, sigbuf : Char*, siglen : Int, rsa : RSA*) : Int

  # fun rsa_sign = RSA_sign(type : Int, m : Char*, m_len : UInt, sigret : Char*, siglen : UInt*, rsa : RSA*)
  # fun rsa_verify = RSA_verify(type : Int, m : Char*, m_len : UInt, sigret : Char*, siglen : UInt*, rsa : RSA*)

  fun rsa_generate_key_ex = RSA_generate_key_ex(rsa : RSA*, bits : Int, e : BigNum*, cb : Void*) : Int
  fun rsa_print = RSA_print(bio : Bio*, rsa : RSA*, offset : Int) : Int

  fun bn_new = BN_new : BigNum*
  fun bn_free = BN_free(bn : BigNum*) : Int
  fun bn_set_word = BN_set_word(bn : BigNum*, w : ULong) : Int
  RSA_F4 = 0x10001_u64

  fun bio_new_file = BIO_new_file(filename : Char*, mode : Char*) : Bio*
  fun bio_new_mem_buf = BIO_new_mem_buf(buf : Void*, len : Int) : Bio*
  fun bio_s_mem = BIO_s_mem : BioMethod*
  fun bio_puts = BIO_puts(bio : Bio*, buf : Char*) : Int
  fun bio_gets = BIO_gets(bio : Bio*, buf : Char*, size : Int) : Int
  fun pem_write_bio_rsa_public_key = PEM_write_bio_RSAPublicKey(bio : Bio*, rsa : RSA*) : Int
  fun pem_write_bio_rsa_private_key = PEM_write_bio_RSAPrivateKey(bio : Bio*, rsa : RSA*, enc : EVP_CIPHER*, kstr : Char*, klen : Int, pem_password_cb : Void*, u : Void*) : Int
  fun pem_write_bio_rsa_pubkey = PEM_write_bio_RSA_PUBKEY(bio : Bio*, rsa : RSA*) : Int
  fun pem_read_bio_rsa_pubkey = PEM_read_bio_RSA_PUBKEY(bio : Bio*, rsa : RSA**, pem_password_cb : Void*, u : Void*) : Int
  # fun pem_write_bio_rsa_private_key = PEM_write_bio_RSAPrivateKey(bio : Bio*, rsa : RSA*, enc : EVP_CIPHER*, kstr : Char*, klen : Int, pem_password_cb : Void*, u : Void*) : Int

  fun pem_read_bio_rsa_public_key = PEM_read_bio_RSAPublicKey(bp : Bio*, rsa : RSA**, pem_password_cb : Void*, u : Void*) : RSA*
  fun pem_read_bio_rsa_private_key = PEM_read_bio_RSAPrivateKey(bp : Bio*, rsa : RSA**, pem_password_cb : Void*, u : Void*) : RSA*

  fun evp_md_free = EVP_MD_free(evp : EVP_MD) : Void
  fun evp_pkey_new = EVP_PKEY_new : Void*
  fun evp_pkey_free = EVP_PKEY_free(pkey : Void*) : Void
  fun evp_pkey_assign = EVP_PKEY_assign(pkey : Void*, type : Int, key : Void*) : Int
  # def evp_pkey_assign_rsa(pkey : Void*, key : Void*) : Int
  #   evp_pkey_assign(pkey, 6, key)
  # end
  fun evp_sign_init_ex = EVP_SignInit_ex(context : EVP_MD_CTX, type : EVP_MD, impl : Void*) : Int
  fun evp_sign_update = EVP_SignUpdate(context : EVP_MD_CTX, d : Void*, count : UInt) : Int
  fun evp_sign_final = EVP_SignFinal(context : EVP_MD_CTX, sig : Char*, s : UInt*, pkey : Void*) : Int
  # fun evp_verify_init_ex = EVP_DigestInit_ex(context : EVP_MD_CTX, type : EVP_MD, impl : Void*) : Int
  # fun evp_verify_update = EVP_DigestUpdate(context : EVP_MD_CTX, d : Void*, count: UInt) : Int
  fun evp_verify_final = EVP_VerifyFinal(context : EVP_MD_CTX, sigbuf : Char*, siglen : UInt, pkey : Void*) : Int
  # struct EVP_PKEY
  #   type : Int
  #   save_type : Int
  #   ameth : Void*
  #   engine : Void*
  #   pmeth_engine : Void*
  #   pkey : Void*
  #   references : Int
  #   lock : Void*
  #   attributes : Void*
  #   save_parameters : Int
  #   pkey0 : PKeyStruct
  #   pkey1 : PKeyStruct
  #   pkey2 : PKeyStruct
  #   pkey3 : PKeyStruct
  #   pkey4 : PKeyStruct
  #   pkey5 : PKeyStruct
  #   pkey6 : PKeyStruct
  #   pkey7 : PKeyStruct
  #   pkey8 : PKeyStruct
  #   pkey9 : PKeyStruct
  #   dirty_count_copy : SizeT

  # end
  # struct PKeyStruct
  #   keymgmt : Void*
  #   provdate : Void*
  #   domainparams : Int
  # end

  RSA_PKCS1_PADDING      = 1
  RSA_SSLV23_PADDING     = 2
  RSA_NO_PADDING         = 3
  RSA_PKCS1_OAEP_PADDING = 4
  RSA_X931_PADDING       = 5
  RSA_PKCS1_PSS_PADDING  = 6

  EVP_PKEY_RSA = 6

  NID_SHA256WithRSAEncryption = 668
  NID_SHA256 = 672

  fun err_get_error = ERR_get_error : ULong
  fun err_error_string_n = ERR_error_string_n(e : ULong, buf : Char*, len : SizeT)
end

module OpenSSL
  enum Signature : LibCrypto::Int
    RSA_SHA1 = 65
    RSA_SHA256 = 668
    RSA_SHA384 = 669
    RSA_SHA512 = 670
    SHA256 = 672
  end

  module RSA
    class Error < OpenSSL::Error
    end

    class KeyPair
      LOCK = Mutex.new
      PADDING_SIZE = 42

      def self.generate(bits = 2048, public_exponent = LibCrypto::RSA_F4) : self
        rsa = LibCrypto.rsa_new
        e = LibCrypto.bn_new
        LibCrypto.bn_set_word e, public_exponent # 65537

        LOCK.synchronize do
          ret = LibCrypto.rsa_generate_key_ex(rsa, bits, e, Pointer(Void).null)
          if ret != 1
            handle_error
          end
        end

        new rsa
      rescue ex
        LibCrypto.rsa_free rsa if rsa
        raise ex
      ensure
        LibCrypto.bn_free e if e
      end

      def initialize(@rsa : Pointer(LibCrypto::RSA))
      end

      def initialize(public_key : IO? = nil, private_key : IO? = nil)
        initialize(
          public_key: public_key ? public_key.gets_to_end : nil,
          private_key: private_key ? private_key.gets_to_end : nil,
        )
      end

      def initialize(public_key : String? = nil, private_key : String? = nil)
        @rsa = LibCrypto.rsa_new

        if public_key
          public_bio = LibCrypto.bio_new_mem_buf(public_key.to_unsafe, public_key.bytesize)
          LibCrypto.pem_read_bio_rsa_pubkey(public_bio, pointerof(@rsa), Pointer(Void).null, Pointer(Void).null)
        end

        if private_key
          private_bio = LibCrypto.bio_new_mem_buf(private_key.to_unsafe, private_key.bytesize)
          LibCrypto.pem_read_bio_rsa_private_key(private_bio, pointerof(@rsa), Pointer(Void).null, Pointer(Void).null)
        end
      ensure
        LibCrypto.BIO_free public_bio if public_bio
        LibCrypto.BIO_free private_bio if public_bio
      end

      def public_key_pem : String
        bio = LibCrypto.BIO_new(LibCrypto.bio_s_mem)
        ret = LibCrypto.pem_write_bio_rsa_pubkey bio, @rsa
        if ret != 1
          handle_error
        end

        bytes = Bytes.new(128)
        String.build do |str|
          while (ret = LibCrypto.bio_gets(bio, bytes.to_unsafe, bytes.size)) > 0
            str << String.new(bytes.to_unsafe, bytes.index(0) || bytes.size)
          end
        end
      ensure
        LibCrypto.BIO_free bio if bio
      end

      def private_key_pem : String
        bio = LibCrypto.BIO_new(LibCrypto.bio_s_mem)
        ret = LibCrypto.pem_write_bio_rsa_private_key(bio, @rsa, Pointer(LibCrypto::EVP_CIPHER).null, Pointer(LibCrypto::Char).null, 0, Pointer(Void).null, Pointer(Void).null)
        if ret != 1
          handle_error
        end

        bytes = Bytes.new(128)
        String.build do |str|
          while (ret = LibCrypto.bio_gets(bio, bytes.to_unsafe, bytes.size)) > 0
            str << String.new(bytes.to_unsafe, bytes.index(0) || bytes.size)
          end
        end
      ensure
        LibCrypto.BIO_free bio if bio
      end

      macro define_encrypt(key, padding)
        def {{key.id}}_encrypt(string : String) : String
          String.new({{key.id}}_encrypt(string.to_slice))
        end

        def {{key.id}}_encrypt(bytes : Bytes) : Bytes
          output = Bytes.new(bytesize)

          LOCK.synchronize do
            ret = LibCrypto.rsa_{{key.id}}_encrypt(
              flen: bytes.size,
              from: bytes.to_unsafe,
              to: output.to_unsafe,
              rsa: @rsa,
              padding: {{padding}},
            )

            if ret == -1
              handle_error
            end
          end

          output
        end
      end
      define_encrypt :public, padding: LibCrypto::RSA_PKCS1_OAEP_PADDING
      define_encrypt :private, padding: LibCrypto::RSA_PKCS1_PADDING

      macro define_decrypt(key, padding)
        def {{key.id}}_decrypt(string : String) : String
          bytes = {{key.id}}_decrypt(string.to_slice)

          # Ensure we strip off trailing null bytes
          # Using the pointer accomplishes this without duplicating the slice
          String.new(bytes.to_unsafe, bytes.index(0) || bytes.size)
        end

        def {{key.id}}_decrypt(bytes : Bytes) : Bytes
          output = Bytes.new(bytesize)

          LOCK.synchronize do
            ret = LibCrypto.rsa_{{key.id}}_decrypt(
              flen: bytes.size,
              from: bytes.to_unsafe,
              to: output.to_unsafe,
              rsa: @rsa,
              padding: {{padding}},
            )

            if ret == -1
              handle_error
            end
          end

          output
        end
      end
      define_decrypt :public, padding: LibCrypto::RSA_PKCS1_PADDING
      define_decrypt :private, padding: LibCrypto::RSA_PKCS1_OAEP_PADDING

      def sign(string : String, signature_type = Signature::SHA256) : String
        String.new(sign(string.to_slice, signature_type))
      end

      def sign(bytes : Bytes, signature_type = Signature::SHA256) : Bytes
        output = Bytes.new(bytesize)

        LOCK.synchronize do
          evp_context = LibCrypto.evp_md_ctx_new
          if evp_context == 0
            handle_error
          end

          key = LibCrypto.evp_pkey_new

          if LibCrypto.evp_pkey_assign(key, LibCrypto::EVP_PKEY_RSA, @rsa) == 0
            handle_error
          end

          if LibCrypto.evp_digestinit_ex(evp_context, LibCrypto.evp_sha256, Pointer(Void).null) == 0
            handle_error
          end

          if LibCrypto.evp_digestupdate(evp_context, bytes.to_unsafe, bytes.size) == 0
            handle_error
          end

          if LibCrypto.evp_sign_final(evp_context, output.to_unsafe, out size, key) != 1
            handle_error
          end
          # ret = LibCrypto.rsa_sign(
          #   type: signature_type,
          #   m: bytes.to_unsafe,
          #   m_length: bytes.size,
          #   sigret: output.to_unsafe,
          #   siglen: out size,
          #   rsa: @rsa,
          # )

          # if ret != 1
          #   handle_error
          # end
        end

        output
      end

      def verify?(signed : String, original : String) : Bool
        verify? signed.to_slice, original.to_slice
      end

      def verify?(signed : Bytes, original : Bytes, signature_type = Signature::SHA256) : Bool
        LOCK.synchronize do
          evp_context = LibCrypto.evp_md_ctx_new
          sha256 = LibCrypto.evp_sha256

          if evp_context == 0
            handle_error
          end

          key = LibCrypto.evp_pkey_new
          rsa = LibCrypto.rsa_public_key_dup(@rsa)
          if rsa.null?
            handle_error
          end

          if LibCrypto.evp_pkey_assign(key, LibCrypto::EVP_PKEY_RSA, rsa) == 0
            handle_error
          end

          if LibCrypto.evp_digestinit_ex(evp_context, sha256, Pointer(Void).null) == 0
            handle_error
          end

          if LibCrypto.evp_digestupdate(evp_context, original.to_unsafe, original.size) == 0
            handle_error
          end

          case LibCrypto.evp_verify_final(evp_context, signed.to_unsafe, signed.size, key)
          when 0
            false
          when 1
            true
          else
            handle_error
          end
          # ret = LibCrypto.rsa_verify(
          #   type: 64,
          #   m: original.to_unsafe,
          #   m_length: original.size,
          #   sigbuf: signed.to_unsafe,
          #   siglen: signed.size,
          #   rsa: @rsa,
          # )

          # ret == 1
        ensure
          LibCrypto.evp_md_ctx_free evp_context if evp_context
          # LibCrypto.evp_md_free sha256 if sha256
          LibCrypto.evp_pkey_free key if key
        end
      end

      def bytesize
        LibCrypto.rsa_size(@rsa)
      end

      def finalize
        LibCrypto.rsa_free @rsa
      end

      macro handle_error
        %error_code = LibCrypto.err_get_error
        %bytes = Bytes.new(256)
        LibCrypto.err_error_string_n(%error_code, %bytes.to_unsafe, 256)
        raise Error.new(String.new(%bytes))
      end
    end
  end
end

# key = OpenSSL::RSA::KeyPair.generate(bits: 2048)
# File.write "public.pem", key.public_key_pem.tap { |pem| puts pem }
# File.write "private.pem", key.private_key_pem.tap { |pem| puts pem }
# # # # 1_000.times do
# # # #   key = OpenSSL::RSA::Key.generate(1024)
# # # # end
# key = OpenSSL::RSA::KeyPair.new(
#   public_key: File.read("public.pem"),
#   private_key: File.read("private.pem"),
# )
# puts key.public_key_pem
# puts key.private_key_pem
# # encrypted = key.public_encrypt("omg 😂🙌🏼")
# # pp encrypted: encrypted

# # decrypted = key.private_decrypt(encrypted)
# # pp decrypted: decrypted

# puts "Loading signing key"
# signing_key = OpenSSL::RSA::KeyPair.new(
#   # public_key: File.read("public.pem"),
#   private_key: File.read("private.pem"),
# )
# puts "Loading verifying key"
# verifying_key = OpenSSL::RSA::KeyPair.new(
#   public_key: File.read("public.pem"),
#   # private_key: File.read("private.pem"),
# )

# string = "omg 😂"
# signature = signing_key.sign(string)
# puts "signed"
# pp signature: signature, verified: verifying_key.verify?(signature, string)

# require "http"
# require "json"
# headers = HTTP::Headers{
#   "Accept-Encoding" => "gzip",
#   "Content-Length" => "2397",
#   "Content-Type" => "application/activity+json",
#   "Date" => "Thu, 31 Oct 2019 03:51:29 GMT",
#   "Digest" => "SHA-256=buBOtBKwQ/sZ6o9IeuOSJlBtTO/Bt6fPO/mafCQ+lMU=",
#   "Host" => "0494686b.ngrok.io",
#   "Signature" => "keyId=\"https://zomglol.wtf/users/jamie#main-key\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date digest content-type\",signature=\"JB4HoT0oOGt9WzMh22sKRo/9Xv4BqC8MimnShMpezq9bhJCjuSe+3OV9K48OAm9bR1p2d5JsmEKvIBem0foculW3c5h1WshHg6xO3ZZhNDSabsj8+Ot0KGQvM1zMYwevTnKkYbBbJ0PU9/OjWcT1+Hv5B427kZBL4iNreZNB3vq8KXbIGdT5LuVmzpVe+vnx/U6sdT0MLSBl9PDjRP7WvEJAaCzrgjDrFU6I66bKFPYR57ojGjs5DvRf/KUXfKwNMw0kKuvSvs3uxTzjqOFpHVtRxndIpOuok9jJ0QpFzjj2F0xyPpLwVpTIKwfqdGhsgP/l2sa1e5yse3hGeoTgZA==\"",
#   "User-Agent" => "http.rb/3.3.0 (Mastodon/3.0.1; +https://zomglol.wtf/)",
#   "X-Forwarded-For" => "167.71.241.231",
#   "X-Forwarded-Proto" => "https",
# }

# signature = "nZgx4hXeyC+HzMUuar5LCnZon6qcmc1R3m94tr7i5fUppDNH4gvXW+e+PrAreM39gLbWdAZTdbrEtj9AsEl+z6lMde5lsnfF3+hfhmrC/1/WYub59y1skvXgg0eeKfUGwaIpWid6Waph1SOKaSu3dMpPp8D+FcXG2ej75G/AV67pACgxs1FOqE2B9Q2ytvI2Dw+ZYodPLSAmD6cl4Bd/ybxSEL6aQ0YN+yVv1K2Cyp3iUyhz6fczSDa4uCORz9PK9DTEGs+oSptaVL41Cl1bjuoY7bUwTpjn60DkZCu6RLaW608QesKxEV71vT9DPunNtpFpBHFm5N4gbjzUdGeBlA=="
# signable_string = "(request-target): post /users/foo/inbox\n" +
#   "host: b4684749.ngrok.io\n" +
#   "date: Sun, 03 Nov 2019 03:42:37 GMT\n" +
#   "digest: SHA-256=+rbjnLHuM0PN4Nl7UbKg8cU1lMJHmd/Sy1zqwyrIPCM=\n" +
#   "content-type: application/activity+json"
# key = OpenSSL::RSA::KeyPair.new(public_key: JSON.parse(HTTP::Client.get("https://zomglol.wtf/users/jamie#main-key", headers: HTTP::Headers { "Accept" => "application/json" }).body).dig("publicKey", "publicKeyPem").as_s)
# begin
# pp verified: key.verify?(String.new(Base64.decode(signature)), signable_string)
# rescue ex
#   pp ex
# end
