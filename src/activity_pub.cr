require "http"
require "json"

module JSON
  macro extend(properties, more_properties)
    ::JSON.mapping({{properties.double_splat}}, {{more_properties.double_splat}})
  end
end

module ActivityPub
  def self.get(uri : String | URI, headers = HTTP::Headers { "Accept" => "application/activity+json, application/ld+json, application+json" })
    HTTP::Client.get(url: uri, headers: headers)
  end

  class Object
    ATTRIBUTES = {
      id: URI?,
      type: String?,
      attachment: Value | Array(Value) | Nil,
      attributed_to: { type: Value?, key: "attributedTo" },
      audience: Value | String | Nil,
      content: String?,
      content_map: { type: Hash(String, String)?, key: "contentMap" },
      name: String?,
      name_map: { type: Hash(String, String)?, key: "nameMap" },
      end_time: Time?,
      generator: Value?,
      icon: Value?,
      image: Value?,
      in_reply_to: { type: URI, nilable: true, key: "inReplyTo" },
      location: Value?,
      preview: Value?,
      published: Time?,
      replies: Collection(Object)?,
      sensitive: Bool?,
      start_time: { type: Time?, key: "startTime" },
      summary: String?,
      summary_map: { type: Hash(String, String)?, key: "summaryMap" },
      tag: Object | Array(Object) | Nil,
      updated: Time?,
      url: { type: URI?, converter: FindURI },
      to: Array(String)?,
      bto: Array(String)?,
      cc: Array(String)?,
      bcc: Array(String)?,
      media_type: { type: String?, key: "mediaType" },
      duration: String?,
      discoverable: { type: Bool?, default: false },
      creator: URI?,
      one_of: { type: Array(Object)?, key: "oneOf" },
    }
    JSON.mapping({{ATTRIBUTES}})

    def initialize(
      @id : URI? = nil,
      @type : String? = nil,
      @summary : String? = nil,
      @in_reply_to : Value? = nil,
      @attributed_to : Value? = nil,
      @published : Time? = nil,
      @url : URI? = nil,
      @media_type : String? = nil,
      @to : Array(String)? = nil,
      @cc : Array(String)? = nil,
      @sensitive : Bool? = false,
      @content : String? = nil,
      @attachment : Value? | Array(Value) = nil,
      @tag : Value? | Array(Value) = nil,
      @replies : Collection(Object)? = nil,
    )
    end
  end

  # Sometimes you don't receive a URL as a string, but as an object. In this
  # case, we need to traverse the object to find the URI string. For example:
  #
  #   {
  #     "url": {
  #       "href": "https://example.com/",
  #     }
  #   }
  module FindURI
    def self.from_json(json : JSON::PullParser) : URI?
      uri = nil

      case json.kind
      when .string?
        uri = URI.parse json.read_string
      when .begin_object?
        hash = json.read_object do |key|
          case key
          when "href"
            uri = URI.parse json.read_string
          else
            json.read_raw
          end
        end
      when .begin_array?
        json.read_array do
          value = from_json json
          uri ||= value
        end
      when .nil?
        json.read_null
        uri = nil
      else
        raise UnexpectedURIType.new("Don't know how to parse a URI from #{json.read_raw.inspect}")
      end

      uri
    end

    def self.to_json(uri : URI, json : JSON::Builder)
      json.string uri.to_s
    end

    class UnexpectedURIType < ::Exception
    end
  end

  class Activity
    DEFAULT_CONTEXT = JSON::Any.new("https://www.w3.org/ns/activitystreams")

    {% begin %}
    JSON.mapping({
      _context: { type: JSON::Any, default: DEFAULT_CONTEXT, key: "@context" },
      {{Object::ATTRIBUTES.double_splat}},
      actor: Value?,
      object: Value?,
      target: Value?,
      result: Value?,
      origin: Value?,
      instrument: Value?,
      signature: Object?,
    })
    {% end %}

    def initialize(
      @id : URI,
      @type : String,
      @actor : Value? = nil,
      @published : Time? = nil,
      @to : Array(String)? = nil,
      @cc : Array(String)? = nil,
      @object : Value? = nil,
      @_context : JSON::Any = DEFAULT_CONTEXT,
    )
    end
  end

  alias Value = URI | Object | Activity

  struct Signature
    JSON.mapping(
      type: String,
      creator: URI,
      created: Time,
      value: { type: String, key: "signatureValue" },
    )
  end

  struct Person
    JSON.mapping(
      id: URI,
      following: URI,
      followers: URI,
      inbox: URI,
      outbox: URI,
      featured: URI,
      preferred_username: { type: String, key: "preferredUsername" },
      name: String,
      summary: { type: String, default: "" },
      manually_approves_followers: { type: Bool?, default: false, key: "manuallyApprovesFollowers" },
      discoverable: { type: Bool?, default: false },
      public_key: { type: PublicKey, key: "publicKey" },
      tag: Array(Tag),
      attachment: Array(Attachment),
      endpoints: Hash(String, String),
      icon: Image?,
      image: Image?,
    )
  end

  struct PublicKey
    JSON.mapping(
      id: URI,
      owner: URI,
      pem: { type: String, key: "publicKeyPem" },
    )
  end

  struct Image
    JSON.mapping(
      media_type: { type: String, key: "mediaType" },
      url: URI,
    )
  end

  struct Attachment
    JSON.mapping(
      type: String,
      media_type: String?,
      url: URI?,
      name: String?,
      value: String?,
      blurhash: String?,
    )
  end

  struct Tag
    JSON.mapping(
      type: String,
      href: String,
      name: String,
    )
  end

  struct Collection(T)
    include Iterable(T)
    include Enumerable(T)

    JSON.mapping(
      id: URI?,
      type: String,
      total_items: { type: UInt64?, key: "totalItems" },
      first: Value?,
    )

    def initialize(
      @id : URI,
      @first : Value,
      @total_items : UInt64? = nil,
      @type : String = "Collection",
    )
    end

    def each
      Iterator(T).new(first)
    end

    def each(& : T ->)
      iterator = each
      loop do
        case value = iterator.next
        when T
          yield value
        when ::Iterator::Stop
          return
        end
      end
      self
    end

    struct Iterator(T)
      include ::Iterator(T)

      def initialize(@uri : URI)
        @current_index = 0
        @current_page = Page(T).from_json(ActivityPub.get(@uri).body)
      end

      def next : T | Stop
        if @current_index < @current_page.size
          @current_page[@current_index].get.tap do
            @current_index += 1
          end
        elsif next_page_uri = @current_page.next
          initialize(uri: next_page_uri)
          self.next
        else
          stop
        end
      end

      struct Page(T)
        JSON.mapping(
          id: URI,
          total_items: { type: UInt64?, key: "totalItems" },
          next: URI?,
          part_of: { type: URI, key: "partOf" },
          ordered_items: { type: Array(Concurrent::Future(T)), converter: URIFetcher(T), key: "orderedItems" },
        )

        def size
          ordered_items.size
        end

        def [](index)
          ordered_items[index]
        end
      end
    end
  end

  struct OrderedCollection(T)
    include Iterable(T)
    include Enumerable(T)

    JSON.mapping(
      id: URI,
      type: String,
      total_items: { type: UInt64?, key: "totalItems" },
      first: Value,
    )

    def initialize(
      @id : URI,
      @total_items : UInt64?,
      @first : Value,
      @type : String = "OrderedCollection",
    )
    end

    def each
      Iterator(T).new(first)
    end

    def each(& : T ->)
      iterator = each
      loop do
        case value = iterator.next
        when T
          yield value
        when ::Iterator::Stop
          return
        end
      end
      self
    end

    struct Iterator(T)
      include ::Iterator(T)

      def initialize(@uri : URI)
        @current_index = 0
        @current_page = Page(T).from_json(ActivityPub.get(@uri).body)
      end

      def initialize(activity : Activity)
        initialize activity.id.not_nil!
      end

      def initialize(object : Object)
        initialize object.id.not_nil!
      end

      def next : T | Stop
        if @current_index < @current_page.size
          @current_page[@current_index].get.tap do
            @current_index += 1
          end
        elsif next_page_uri = @current_page.next
          initialize(uri: next_page_uri)
          self.next
        else
          stop
        end
      end

      struct Page(T)
        JSON.mapping(
          id: URI,
          total_items: { type: UInt64?, key: "totalItems" },
          next: URI?,
          part_of: { type: URI, key: "partOf" },
          ordered_items: { type: Array(Concurrent::Future(T)), converter: URIFetcher(T), key: "orderedItems" },
        )

        def size
          ordered_items.size
        end

        def [](index)
          ordered_items[index]
        end
      end
    end
  end

  module URIFetcher(T)
    def self.from_json(json : ::JSON::PullParser) : Array(Concurrent::Future(T))
      values = Array(Concurrent::Future(T)).new
      json.read_array do
        case json.kind
        when .string?
          url = json.read_string
          values << future do
            T.from_json(ActivityPub.get(url).body)
          end
        when .begin_object?
          value = T.new(json)
          values << future { value }
        else
          raise UnexpectedType.new("Expected String or JSON object, got: #{json.kind}")
        end
      end

      values
    end

    class UnexpectedType < ::Exception
    end
  end
end

class URI
  def self.new(parser : JSON::PullParser)
    if parser.string_value !~ %r{://}
      raise JSON::ParseException.new("Expected URI-formatted string, got: #{parser.string_value.inspect}", parser.line_number, parser.column_number)
    end
    parse(parser.read_string)
  end

  def inspect
    "URI(#{to_s})"
  end

  def to_json(io)
    to_s.to_json io
  end
end
