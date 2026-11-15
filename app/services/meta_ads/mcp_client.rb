# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"

module MetaAds
  # JSON-RPC client for Meta's hosted Ads MCP (`https://mcp.facebook.com/ads`).
  # Uses the merchant connection token as Bearer. Does not replace Graph sync by itself —
  # callers decide which tools to invoke. Tokens and Meta error text never leave coded errors.
  class McpClient
    MAX_BODY_BYTES = 5.megabytes
    DEFAULT_URL = "https://mcp.facebook.com/ads"

    class Error < StandardError
      CODE = "unavailable"
      attr_reader :code, :retry_after

      def initialize(code = self.class::CODE, retry_after: nil)
        @code = code
        @retry_after = retry_after
        super("Meta Ads MCP: #{code}")
      end
    end
    class AuthError < Error; CODE = "invalid_token"; end
    class PermissionError < Error; CODE = "permission_denied"; end
    class RateLimitError < Error; CODE = "rate_limited"; end
    class TransientError < Error; CODE = "unavailable"; end
    class InvalidResponseError < Error; CODE = "invalid_response"; end
    class ToolError < Error; CODE = "tool_error"; end

    Response = Struct.new(:id, :result, :error, keyword_init: true) do
      def ok?
        error.blank?
      end

      def tool_text
        Array(result&.dig("content")).filter_map { |part| part["text"] if part.is_a?(Hash) }.join("\n")
      end

      def tool_json
        text = tool_text
        return if text.blank?

        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end
    end

    def initialize(connection: nil, token: nil, transport: nil, url: nil)
      valid_connection = connection.is_a?(MetaAds::Connection) && connection.active?
      raise ArgumentError, "Active Meta connection or token required" unless valid_connection || token.present?

      @connection = valid_connection ? connection : nil
      @token = token
      @transport = transport
      @url = url.presence || ENV["META_ADS_MCP_URL"].presence || DEFAULT_URL
    end

    def list_tools
      rpc("tools/list")
    end

    def call_tool(name, arguments = {})
      raise ArgumentError, "tool name required" if name.blank?

      rpc("tools/call", name: name.to_s, arguments: arguments.is_a?(Hash) ? arguments : {})
    end

    private

    def rpc(method, params = nil)
      token = @token || @connection.access_token
      raise AuthError.new if token.blank? || (@token.blank? && @connection.token_expired?)

      id = SecureRandom.uuid
      body = { jsonrpc: "2.0", id: id, method: method }
      body[:params] = params if params
      uri = URI(@url)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json, text/event-stream"
      request.body = JSON.generate(body)

      status, raw, headers = perform(uri, request)
      raise InvalidResponseError.new if raw.bytesize > MAX_BODY_BYTES

      payload = parse_body(raw, headers)
      raise_http!(status, headers)
      raise InvalidResponseError.new unless payload.is_a?(Hash)

      if (err = payload["error"]).is_a?(Hash)
        raise_rpc_error!(err)
      end

      result = payload["result"]
      if method == "tools/call" && result.is_a?(Hash) && result["isError"]
        raise ToolError.new
      end

      Response.new(id: payload["id"], result: result, error: nil)
    rescue JSON::ParserError, EncodingError
      raise InvalidResponseError.new
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      raise TransientError.new
    end

    def parse_body(raw, headers)
      content_type = headers["content-type"].to_s
      if content_type.include?("text/event-stream") || raw.start_with?("event:", "data:")
        data_lines = raw.each_line.filter_map { |line| line.delete_prefix("data:").strip if line.start_with?("data:") }
        raise InvalidResponseError.new if data_lines.empty?

        JSON.parse(data_lines.last)
      else
        JSON.parse(raw)
      end
    end

    def raise_http!(status, headers)
      return if status.between?(200, 299)

      retry_after = headers["retry-after"].to_i
      raise RateLimitError.new(retry_after: retry_after.positive? ? retry_after : nil) if status == 429
      raise AuthError.new if status == 401
      raise PermissionError.new if status == 403
      raise TransientError.new if status >= 500

      raise InvalidResponseError.new
    end

    def raise_rpc_error!(err)
      message = err["message"].to_s.downcase
      code = err["code"]
      raise AuthError.new if message.include?("auth") || message.include?("token") || code == -32_000
      raise PermissionError.new if message.include?("permission") || message.include?("scope")
      raise RateLimitError.new if message.include?("rate") || message.include?("limit")
      raise ToolError.new if message.include?("tool")

      raise InvalidResponseError.new
    end

    def perform(uri, request)
      if @transport
        response = @transport.call(uri, request)
        return [ response.code.to_i, response.body.to_s, response.to_hash.transform_values { |value| Array(value).first } ]
      end

      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 45
      http.start do |connection|
        connection.request(request) do |response|
          body = +""
          response.read_body do |chunk|
            raise InvalidResponseError.new if body.bytesize + chunk.bytesize > MAX_BODY_BYTES

            body << chunk
          end
          return [ response.code.to_i, body, response.to_hash.transform_values { |value| Array(value).first } ]
        end
      end
    end
  end
end
