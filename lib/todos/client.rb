# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require "todos/error"

module Todos
  class Client
    JSON_CONTENT_TYPE = "application/json"

    def initialize(base_url: ENV["TODOS_BASE_URL"], api_key: ENV["TODOS_API_KEY"])
      @base_url = base_url.to_s.strip
      @api_key = api_key.to_s.strip
    end

    def request(method, path, body: nil, query: {})
      validate_config!
      uri = build_uri(path, query)
      request = build_request(method, uri, body)
      response = perform(uri, request)
      parse_response(response)
    rescue Todos::Error
      raise
    rescue URI::InvalidURIError => e
      raise Error.new("Invalid TODOS_BASE_URL: #{e.message}", code: "CONFIG_ERROR")
    rescue SystemCallError, SocketError, Timeout::Error, EOFError => e
      raise Error.new("Request failed: #{e.message}", code: "NETWORK_ERROR")
    end

    private

    def validate_config!
      missing = []
      missing << "TODOS_API_KEY" if @api_key.empty?
      missing << "TODOS_BASE_URL" if @base_url.empty?
      return if missing.empty?

      raise Error.new(
        "Missing required environment variable#{missing.length == 1 ? "" : "s"}: #{missing.join(", ")}",
        code: "CONFIG_ERROR"
      )
    end

    def build_uri(path, query)
      base = URI.parse(@base_url)
      unless base.is_a?(URI::HTTP) && base.host
        raise Error.new("TODOS_BASE_URL must be an http(s) URL", code: "CONFIG_ERROR")
      end

      base_path = base.path.to_s.sub(%r{/+\z}, "")
      request_path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
      base.path = "#{base_path}#{request_path}"
      base.query = URI.encode_www_form(query) unless query.empty?
      base
    end

    def build_request(method, uri, body)
      klass = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete
      }.fetch(method.to_sym) do
        raise Error.new("Unsupported HTTP method: #{method}", code: "INTERNAL_ERROR")
      end

      request = klass.new(uri)
      request["Accept"] = JSON_CONTENT_TYPE
      request["Authorization"] = "Bearer #{@api_key}"
      if body
        request["Content-Type"] = JSON_CONTENT_TYPE
        request.body = JSON.generate(body)
      end
      request
    end

    def perform(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30
      http.request(request)
    end

    def parse_response(response)
      status = response.code.to_i
      return nil if status == 204

      parsed = parse_json(response.body)
      if status.between?(200, 299)
        unless parsed
          raise Error.new("HTTP #{status} returned a non-JSON response", code: "NON_JSON_RESPONSE")
        end

        return parsed
      end

      message = error_message(parsed)
      message ||= "HTTP #{status} returned a non-JSON response"
      raise Error.new(message, code: "HTTP_#{status}")
    end

    def parse_json(body)
      return if body.to_s.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def error_message(parsed)
      return unless parsed.is_a?(Hash)

      error = parsed["error"]
      return error.to_s unless error.nil? || error.to_s.empty?

      errors = parsed["errors"]
      return errors.join("; ") if errors.is_a?(Array)
      return errors.values.flatten.join("; ") if errors.is_a?(Hash)

      errors.to_s unless errors.nil? || errors.to_s.empty?
    end
  end
end
