require "spec"
require "http"
require "dotenv"
Dotenv.load

def build_context(method, path, headers = HTTP::Headers.new, body = nil, &block) : HTTP::Client::Response
  headers = headers.dup

  headers["Accept"] = "application/json"
  headers["Content-Type"] = "application/json" if %w[POST PUT PATCH].includes? method.upcase
  request = HTTP::Request.new(
    method: method,
    resource: path,
    headers: headers,
    body: body,
  )

  response_body = IO::Memory.new
  response = HTTP::Server::Response.new(io: response_body)

  yield HTTP::Server::Context.new(request, response)
  response.flush
  response.close

  HTTP::Client::Response.from_io(response_body.rewind, ignore_body: false, decompress: false)
end
