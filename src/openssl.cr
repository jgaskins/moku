lib LibCrypto
  fun RSA_new : Pointer(RSA)

  struct BIGNUM
    d : ULong*
    top : Int
    dmax : Int
    neg : Int
    flags : Int
  end
end

module OpenSSL
  class PKey
    class RSA
      def initialize(io : IO)
        initialize io.gets_to_end
      end

      def initialize(pem : String)
        initialize pem.to_slice
      end

      def initialize(@pem : Bytes)
      end
    end
  end

  module X509
    class Certificate
      def public_key

      end

      def private_key

      end
    end
  end
end
