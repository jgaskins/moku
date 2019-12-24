require "http"
require "json"
require "ecr"

module Route
  def route(context, &block : Request, Response, HTTP::Session ->)
    request = Request.new(context.request)
    response = Response.new(context.response)

    yield request, response, context.session
  end

  macro render(template, to io = response)
    ECR.embed "views/{{template.id}}.ecr", {{io}}
  end

  class Request
    delegate headers, path, :headers=, body, method, original_path, to: @request

    @handled = false

    def initialize(@request : HTTP::Request)
      @request.original_path = @request.@original_path || @request.path
    end

    def params
      @request.query_params
    end

    def root
      return if handled?

      is("/") { yield }
      is("") { yield }
    end

    macro handle_method(*methods)
      {% for method in methods %}
        def {{method.id.downcase}}
          return if handled?

          if @request.method == {{method.stringify.upcase}}
            yield
            handled!
          end
        end

        def {{method.id.downcase}}(capture : Symbol)
          is(capture) { |capture| {{method.id.downcase}} { yield capture } }
        end

        def {{method.id.downcase}}(path : String)
          is(path) { {{method.id.downcase}} { yield } }
        end
      {% end %}
    end

    handle_method get, post, put, patch, delete

    def is(path : String = "")
      return if handled?

      check_path = path.sub(%r(\A/), "")
      actual = @request.path.sub(%r(\A/), "")

      old_path = @request.path
      if check_path == actual
        @request.path = ""
        yield
        handled!
      end
    ensure
      @request.path = old_path if old_path
    end

    def is(path : Symbol)
      return if handled?

      old_path = @request.path
      match = %r(\A/?[^/]+\z).match @request.path.sub(%r(\A/), "")
      if match
        @request.path = @request.path.sub(%r(\A/#{match[0]}), "")

        yield match[0]
        handled!
      end
    ensure
      if old_path
        @request.path = old_path
      end
    end

    def on(*paths : String)
      paths.each do |path|
        on(path) { yield }
      end
    end

    def on(path : String)
      return if handled?

      if match?(path)
        begin
          old_path = @request.path
          @request.path = @request.path.sub(/\A\/?#{path}/, "")
          yield
        ensure
          @request.path = old_path.not_nil!
        end
      end
    end

    def on(capture : Symbol)
      return if handled?

      old_path = @request.path
      match = %r(\A/?[^/]+).match @request.path.sub(%r(\A/), "")
      if match
        @request.path = @request.path.sub(%r(\A/#{match[0]}), "")

        yield match[0]
      end
    ensure
      if old_path
        @request.path = old_path
      end
    end

    def params(*params)
      return if handled?
      return if !params.all? { |param| @request.query_params.has_key? param }

      yield params.map { |key| @request.query_params[key] }
      handled!
    end

    def miss
      return if handled?

      yield
      handled!
    end

    def json?
      path.ends_with?("json") || headers["Content-Type"]? =~ /json/ || headers["Accept"]? =~ /json/
    end

    def url : URI
      @uri ||= URI.parse("https://#{@request.host_with_port}/#{@request.path}")
    end

    private def match?(path : String)
      @request.path.starts_with?(path) || @request.path.starts_with?("/#{path}")
    end

    def handled?
      @request.handled?
    end

    def handled!
      @request.handled!
    end
  end

  class Response < IO
    @response : HTTP::Server::Response

    delegate headers, read, status, :status=, to: @response

    def initialize(@response)
    end

    def redirect(path)
      @response.status = HTTP::Status::FOUND
      @response.headers["Location"] = path
    end

    def json(serializer)
      @response.headers["Content-Type"] = "application/json"
      serializer.to_json @response
    end

    def json(**stuff)
      @response.headers["Content-Type"] = "application/json"
      stuff.to_json @response
    end

    def write(bytes : Bytes) : Nil
      @response.write bytes
    end
  end

  class UnauthenticatedException < Exception
  end

  class RequestHandled < Exception
  end
end

module HTTP
  abstract class Session
    def initialize(@store : Store, @context : HTTP::Server::Context)
    end

    abstract def [](key)

    abstract def []=(key, value)
  end

  abstract class Store
    include HTTP::Handler

    @key : String
    @path : String

    def initialize(@key, @path)
    end
  end
end

require "http"
require "json"
require "uuid"
require "redis"

module HTTP
  class Session
    class RedisStore < Store
      getter key

      def initialize(
        @key : String,
        @path : String = "/",
        @redis = Redis::PooledClient.new,
      )
      end

      def call(context : HTTP::Server::Context)
        context.session = Session.new(self, context)

        unless session_id = context.request.cookies[@key]?.try(&.value)
          session_id = UUID.random.to_s
          context.response.cookies << Cookie.new(@key, session_id)
        end

        call_next context

        save "#{@key}-#{session_id}", context.session.as(Session)
      end

      def load(key : String) : Hash(String, JSON::Any)
        value = JSON.parse(@redis.get(key) || "{}")
        if value.raw.nil?
          value = JSON::Any.new({} of String => JSON::Any)
        end

        value.as_h
      end

      def save(key : String, session : Session)
        return unless session.modified?

        @redis.set key, session.json
      end

      class Session < ::HTTP::Session
        @data : Hash(String, JSON::Any)?
        @modified : Bool = false

        def [](key : String)
          data[key]
        end

        def []?(key : String)
          data[key]?
        end

        def []=(key : String, value : JSON::Any::Type)
          data[key] = JSON::Any.new(value)
          @modified = true
        end

        def []=(key : String, value : Int)
          data[key] = JSON::Any.new(value.to_i64)
          @modified = true
        end

        def delete(key : String)
          data.delete key
          @modified = true
        end

        def modified?
          @modified
        end

        private def data
          if cookie = @context.request.cookies[@store.key]?
            cookie.value ||= UUID.random.to_s
          else
            cookie = @context.request.cookies[@store.key] = UUID.random.to_s
          end

          redis_key = "#{@store.key}-#{cookie.value}"
          (@data ||= @store.as(RedisStore).load(redis_key)).not_nil!
        end

        def json
          @data.to_json
        end
      end
    end
  end
end

module HTTP
  class Server
    class Context
      @session : HTTP::Session?

      def session : HTTP::Session
        @session ||= BlankSession.new(
          store: BlankSession::Store.new("", ""),
          context: self,
        )
      end

      def session=(session : HTTP::Session) : Nil
        @session = session
      end

      class BlankSession < HTTP::Session
        def initialize(@store, @context)
        end

        def [](key)
        end

        def []=(key, value)
        end

        def []?(key)
        end

        def delete(key)
        end

        class Store < HTTP::Store
          def call(context)
          end

          def key
            ""
          end
        end
      end
    end
  end

  class Request
    # We mutate the request path as we traverse the routing tree so we need to
    # be able to know the original path.
    property! original_path : String
    getter? handled = false

    def handled!
      @handled = true
    end
  end
end
