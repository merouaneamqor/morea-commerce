# frozen_string_literal: true

require "net/http"
require "json"

module MetaAds
  # Thin read-only Graph API wrapper. The caller passes a connection already resolved through the
  # authorized store. The token travels in the Authorization header, never in a URL, and Meta's own
  # error text is never copied into messages: failures carry a fixed code.
  class Client
    MAX_BODY_BYTES = 5.megabytes
    MAX_PAGES = 200
    PAGE_SIZE = 200

    class Error < StandardError
      CODE = "unavailable"
      attr_reader :code, :retry_after

      def initialize(code = self.class::CODE, retry_after: nil)
        @code = code
        @retry_after = retry_after
        super("Meta API: #{code}")
      end
    end
    # Token expired, revoked or invalid. Permanent until the merchant reconnects.
    class AuthError < Error; CODE = "invalid_token"; end
    # Permission or asset access removed. Permanent until the merchant reconnects.
    class PermissionError < Error; CODE = "permission_denied"; end
    # Usage limit reached. Retry later with backoff.
    class RateLimitError < Error; CODE = "rate_limited"; end
    # Network, 5xx or temporary Meta failure. Retry later.
    class TransientError < Error; CODE = "unavailable"; end
    class InvalidResponseError < Error; CODE = "invalid_response"; end

    AUTH_CODES = [ 102, 190 ].freeze
    PERMISSION_CODES = [ 10, 200..299, 278 ].freeze
    RATE_LIMIT_CODES = [ 4, 17, 32, 613, 80000..80014 ].freeze

    Response = Struct.new(:data, :paging_after, :usage_pct, keyword_init: true)

    # transport: ->(uri, request) { response } is for tests; nothing live is called when it is given.
    # Either an active connection (merchant token) or an explicit token (app token for OAuth) is required.
    def initialize(connection: nil, token: nil, transport: nil)
      valid_connection = connection.is_a?(MetaAds::Connection) && connection.active?
      raise ArgumentError, "Active Meta connection or token required" unless valid_connection || token.present?

      @connection = valid_connection ? connection : nil
      @token = token
      @transport = transport
    end

    # Form POST, used only for OAuth token exchange. Secrets travel in the body, never in the URL.
    def post(path, form = {})
      request(path, {}, form: form)
    end

    # Single request. Returns the parsed body and the highest reported usage percentage.
    def get(path, params = {})
      request(path, params)
    end

    # Follows cursors until the collection is complete. Returns all rows and the highest usage seen.
    def collect(path, params = {})
      rows = []
      usage = 0
      after = nil
      MAX_PAGES.times do
        response = request(path, params.merge(limit: PAGE_SIZE, after: after).compact)
        rows.concat(response.data)
        usage = [ usage, response.usage_pct ].max
        after = response.paging_after
        return Response.new(data: rows, paging_after: nil, usage_pct: usage) if after.blank?
      end
      raise InvalidResponseError.new
    end

    private

    def request(path, params, form: nil)
      raise ArgumentError, "Invalid Graph path" unless path.to_s.match?(%r{\A[A-Za-z0-9_/.]+\z}) && !path.to_s.include?("..")

      token = @token || @connection.access_token
      raise AuthError.new if token.blank? || (@token.blank? && @connection.token_expired?)

      uri = URI("#{Config::BASE_URL}/#{Config.api_version}/#{path.to_s.delete_prefix("/")}")
      uri.query = URI.encode_www_form(params.transform_values { |value| value.is_a?(Array) ? value.join(",") : value }) if params.any?
      request = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request.set_form_data(form) if form
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      status, body, headers = perform(uri, request)
      raise InvalidResponseError.new if body.bytesize > MAX_BODY_BYTES

      payload = JSON.parse(body)
      raise InvalidResponseError.new unless payload.is_a?(Hash)

      usage = usage_pct(headers)
      raise_for_error!(status, payload, headers)
      data = payload["data"].is_a?(Array) ? payload["data"] : [ payload ]
      Response.new(data: data, paging_after: payload.dig("paging", "next").present? ? payload.dig("paging", "cursors", "after") : nil, usage_pct: usage)
    rescue JSON::ParserError, EncodingError
      raise InvalidResponseError.new
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      raise TransientError.new
    end

    def perform(uri, request)
      if @transport
        response = @transport.call(uri, request)
        return [ response.code.to_i, response.body.to_s, response.to_hash.transform_values { |value| Array(value).first } ]
      end

      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 20
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

    def raise_for_error!(status, payload, headers)
      error = payload["error"]
      return if status.between?(200, 299) && !error.is_a?(Hash)

      code = error.is_a?(Hash) ? error["code"].to_i : 0
      retry_after = retry_after_seconds(headers)
      raise RateLimitError.new(retry_after: retry_after) if status == 429 || matches?(RATE_LIMIT_CODES, code)
      raise AuthError.new if status == 401 || matches?(AUTH_CODES, code)
      raise PermissionError.new if status == 403 || matches?(PERMISSION_CODES, code)
      raise TransientError.new if status >= 500 || [ 1, 2 ].include?(code)

      raise InvalidResponseError.new
    end

    def matches?(codes, code)
      codes.any? { |entry| entry === code }
    end

    # Highest utilisation across Meta's usage headers, 0..100.
    def usage_pct(headers)
      values = []
      values.concat(header_json(headers, "x-app-usage").values_at("call_count", "total_cputime", "total_time"))
      values.concat(header_json(headers, "x-ad-account-usage").values_at("acc_id_util_pct"))
      header_json(headers, "x-business-use-case-usage").each_value do |entries|
        Array(entries).each { |entry| values.concat(entry.values_at("call_count", "total_cputime", "total_time")) if entry.is_a?(Hash) }
      end
      values.filter_map { |value| Float(value, exception: false) }.max.to_f.clamp(0, 100)
    end

    def retry_after_seconds(headers)
      header_json(headers, "x-business-use-case-usage").each_value do |entries|
        Array(entries).each do |entry|
          minutes = entry["estimated_time_to_regain_access"].to_i if entry.is_a?(Hash)
          return minutes * 60 if minutes&.positive?
        end
      end
      nil
    end

    def header_json(headers, name)
      parsed = JSON.parse(headers[name].to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
