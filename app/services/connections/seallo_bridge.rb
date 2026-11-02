require "openssl"
require "net/http"

module Connections
  # A separate server-to-server key authenticates the embedded app. It never
  # authorizes a workspace: a short-lived code issued to authorized staff does.
  class SealloBridge
    class Error < StandardError; end
    MAX_BODY = 1.megabyte

    def self.authenticate!(body:, timestamp:, signature:)
      secret = ENV["SEALLO_BRIDGE_SECRET"].to_s
      raise Error, "config_missing" if secret.bytesize < 32
      raise Error, "invalid_signature" unless body.bytesize <= MAX_BODY && timestamp.to_s.match?(/\A\d{10}\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300

      expected = OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{body}")
      raise Error, "invalid_signature" unless signature.to_s.bytesize == 64 && ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def self.graphql(shop:, query:, variables: {})
      request(operation: "graphql", shop: shop, query: query, variables: variables)
    end

    def self.entitlement(shop:)
      request(operation: "entitlement", shop: shop)
    end

    def self.request(**input)
      origin = URI(ENV.fetch("SEALLO_APP_URL", ""))
      raise Error, "config_missing" unless origin.scheme == "https" && origin.host.present? && origin.userinfo.nil? && [ "", "/" ].include?(origin.path) && origin.query.nil? && origin.fragment.nil?

      uri = URI.join(origin.to_s, "/api/morea")
      body = JSON.generate(input)
      timestamp = Time.current.to_i.to_s
      secret = ENV["SEALLO_BRIDGE_SECRET"].to_s
      raise Error, "config_missing" if secret.bytesize < 32

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Seallo-Timestamp"] = timestamp
      request["X-Seallo-Signature"] = OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{body}")
      request.body = body
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 15
      http.write_timeout = 10
      http.max_retries = 0
      response_body = +""
      status = nil
      http.start do |client|
        client.request(request) do |response|
          status = response.code.to_i
          response.read_body do |chunk|
            raise Error, "invalid_response" if response_body.bytesize + chunk.bytesize > MAX_BODY
            response_body << chunk
          end
        end
      end
      raise Error, "rate_limited" if status == 429
      raise Error, "invalid_credentials" if [ 401, 403, 404, 410 ].include?(status)
      raise Error, "unavailable" unless status == 200

      payload = JSON.parse(response_body)
      raise Error, "invalid_response" unless payload.is_a?(Hash) && payload["data"].is_a?(Hash)
      raise Error, "missing_scopes" if payload["errors"].present?

      payload["data"]
    rescue URI::InvalidURIError, JSON::ParserError
      raise Error, "invalid_response"
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError
      raise Error, "unavailable"
    end
  end
end
