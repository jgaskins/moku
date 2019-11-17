require "openssl"
require "../sign"

module Moku
  module Services
    struct SendActivity
      def self.[](activity, service_uri, key_pair)
        new.call activity, service_uri, key_pair
      end

      def call(activity : ActivityPub::Activity, service_uri : URI, key_pair : OpenSSL::RSA::KeyPair)
        body = activity.to_json

        # pp JSON.parse body

        request_target = "post #{service_uri.path}"
        host = service_uri.host
        date = Time::Format::HTTP_DATE.format(activity.published || Time.utc)
        digest = "SHA-256=#{OpenSSL::Digest.new("SHA256").update(body).base64digest.strip}"
        content_type = "application/activity+json"
        signable_string = {
          "(request-target)": request_target,
          host: host,
          date: date,
          digest: digest,
          "content-type": content_type,
        }.map { |key, value| "#{key}: #{value}" }.join('\n')
        signature = Base64.strict_encode(key_pair.sign(signable_string))

        HTTP::Client.post(
          url: service_uri,
          headers: HTTP::Headers {
            "Date" => date,
            "Host" => host.to_s,
            "Digest" => digest,
            "Content-Type" => content_type,
            "Signature" => {
              %{keyId="#{activity.actor.to_s}"},
              %{algorithm="rsa-sha256"},
              %{headers="(request-target) host date digest content-type"},
              %{signature="#{signature}"},
            }.join(',')
          },
          body: body,
        )
      end
    end
  end
end
