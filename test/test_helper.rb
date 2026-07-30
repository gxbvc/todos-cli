# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "socket"
require "tmpdir"
require "uri"

TOOL_ROOT = File.expand_path("..", __dir__)
EXECUTABLE = File.join(TOOL_ROOT, "todos-cli")

class StubServer
  attr_reader :requests

  REASONS = {
    200 => "OK",
    201 => "Created",
    204 => "No Content",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    422 => "Unprocessable Entity",
    500 => "Internal Server Error"
  }.freeze

  def initialize(*responses)
    @responses = responses
    @requests = Queue.new
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { serve }
  end

  def url
    "http://127.0.0.1:#{@server.local_address.ip_port}"
  end

  def finish
    @thread.join(2)
    raise "Stub server did not finish" if @thread.alive?
  ensure
    @server.close unless @server.closed?
  end

  private

  def serve
    @responses.each do |response|
      socket = @server.accept
      request_line = socket.gets
      method, target, = request_line.split
      headers = {}
      while (line = socket.gets)
        break if line == "\r\n"

        key, value = line.split(":", 2)
        headers[key.downcase] = value.to_s.strip
      end
      body = socket.read(headers.fetch("content-length", "0").to_i)
      @requests << { method: method, target: target, headers: headers, body: body }
      write_response(socket, response)
      socket.close
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def write_response(socket, response)
    status = response.fetch(:status, 200)
    body = response.key?(:body) ? response[:body].to_s : JSON.generate(id: 99, status: "open")
    headers = {
      "Content-Type" => response.fetch(:content_type, "application/json"),
      "Content-Length" => body.bytesize,
      "Connection" => "close"
    }.merge(response.fetch(:headers, {}))
    socket.write("HTTP/1.1 #{status} #{REASONS.fetch(status, "Response")}\r\n")
    headers.each { |key, value| socket.write("#{key}: #{value}\r\n") }
    socket.write("\r\n")
    socket.write(body)
  end
end

module CLITestHelpers
  def run_cli(*args, server:, cwd: TOOL_ROOT, executable: EXECUTABLE, env: {})
    process_env = {
      "TODOS_API_KEY" => "test-key",
      "TODOS_BASE_URL" => server.url,
      "BUNDLE_GEMFILE" => nil,
      "HTTP_PROXY" => nil,
      "http_proxy" => nil
    }.merge(env)
    stdout, stderr, status = Open3.capture3(process_env, executable, *args, chdir: cwd)
    server.finish
    [JSON.parse(stdout), stderr, status]
  end

  def json_body(request)
    request[:body].empty? ? nil : JSON.parse(request[:body])
  end
end

class Minitest::Test
  include CLITestHelpers
end
