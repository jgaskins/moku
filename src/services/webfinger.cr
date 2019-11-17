module Moku
  module Services
    struct Webfinger
      struct Result
        JSON.mapping(
          subject: String,
          aliases: Array(URI),
          links: Array(Link),
        )
      end

      struct Link
        JSON.mapping(
          rel: String,
          type: String?,
          href: URI?,
          template: URI?,
        )
      end

      def call(resource : String) : Result
        if match = resource.match(/@(.*)\z/)
          host = match[1]
          Result.from_json(
            HTTP::Client.get(
              url: URI.parse("https://#{host}/.well-known/webfinger?resource=#{resource}"),
              headers: HTTP::Headers { "accept" => "application/json" },
            ).body
          )
        else
          raise ResourceNotFound.new("Cannot webfinger resource: #{resource}")
        end
      end

      class Exception < ::Exception
      end
      class ResourceNotFound < Exception
      end
    end
  end
end
