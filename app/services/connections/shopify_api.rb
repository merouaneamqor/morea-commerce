# frozen_string_literal: true

require "net/http"
require "json"

module Connections
  # The caller supplies a connection already scoped to its authorized workspace.
  # The shared Seallo app obtains each shop's offline tokens through merchant OAuth approval.
  class ShopifyApi
    API_VERSION = "2026-10"
    REQUIRED_SCOPES = %w[write_orders read_customers read_products].freeze
    MAX_BODY_BYTES = 1.megabyte
    TRANSIENT_ERRORS = %w[rate_limited unavailable invalid_response config_missing].freeze
    VERIFY_QUERY = "query { shop { myshopifyDomain } currentAppInstallation { accessScopes { handle } } }"

    class Error < StandardError
      CODES = %w[config_missing credentials_missing disconnected invalid_credentials shop_not_permitted missing_scopes source_mismatch rate_limited unavailable invalid_response].freeze
      attr_reader :code

      def initialize(code)
        @code = CODES.include?(code) ? code : "unavailable"
        super("Shopify API: #{@code}")
      end
    end

    def initialize(connection:, transport: nil)
      @connection = connection
      @transport = transport
    end

    def verify!
      synchronize do
        validate_connection!
        verify_token!
        true
      end
    end

    # The OAuth callback caller must already have validated HMAC, state and shop.
    def authorize!(code:)
      synchronize do
        validate_connection!
        raise Error.new("credentials_missing") if code.blank?

        exchange_token!(code: code, expiring: "1")
        verify_token!
        true
      end
    end

    # Internal service API. Never accept arbitrary GraphQL from an HTTP request.
    def graphql(query:, variables: {})
      synchronize do
        validate_connection!
        verify_token! unless cached_token? && @connection.shopify_api_verified_at.present?
        graphql_data(query: query, variables: variables)
      end
    end

    private

    def synchronize
      result = nil
      failure = nil
      @connection.with_lock do
        begin
          result = yield
        rescue Error, ActiveSupport::MessageEncryptor::InvalidMessage => error
          error = Error.new("invalid_credentials") unless error.is_a?(Error)
          # Keep failure state in the committed transaction, then raise outside it.
          attributes = { shopify_granted_scopes: [], shopify_api_verified_at: nil, shopify_api_error_code: error.code }
          unless TRANSIENT_ERRORS.include?(error.code)
            attributes.merge!(shopify_access_token: nil, shopify_access_token_expires_at: nil,
              shopify_refresh_token: nil, shopify_refresh_token_expires_at: nil)
          end
          @connection.update!(attributes)
          failure = error
        end
      end
      raise failure if failure

      result
    end

    def validate_connection!
      raise Error.new("disconnected") unless @connection.active? && @connection.provider == "shopify"
      unless @connection.external_domain.to_s.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/) && @connection.external_domain.to_s.bytesize <= 253
        raise Error.new("source_mismatch")
      end
      if ENV["SHOPIFY_CLIENT_ID"].blank? || ENV["SHOPIFY_CLIENT_SECRET"].blank?
        raise Error.new("config_missing")
      end
      raise Error.new("credentials_missing") unless @connection.shopify_oauth
    end

    def cached_token?
      @connection.shopify_access_token.present? &&
        @connection.shopify_access_token_expires_at.present? &&
        @connection.shopify_access_token_expires_at > 60.seconds.from_now
    end

    def verify_token!
      refresh_token! unless cached_token?
      data = graphql_data(query: VERIFY_QUERY, variables: {})
      unless data["shop"].is_a?(Hash) && data["currentAppInstallation"].is_a?(Hash)
        raise Error.new("invalid_response")
      end
      domain = data.dig("shop", "myshopifyDomain")
      raise Error.new("source_mismatch") unless domain == @connection.external_domain

      entries = data.dig("currentAppInstallation", "accessScopes")
      unless entries.is_a?(Array) && entries.all? { |scope| scope.is_a?(Hash) && scope["handle"].is_a?(String) }
        raise Error.new("invalid_response")
      end
      scopes = entries.map { |scope| scope.fetch("handle") }.uniq.sort
      effective_scopes = scopes.dup
      effective_scopes << "read_customers" if scopes.include?("write_customers")
      effective_scopes << "read_products" if scopes.include?("write_products")
      raise Error.new("missing_scopes") unless (REQUIRED_SCOPES - effective_scopes).empty?

      @connection.update!(shopify_granted_scopes: scopes, shopify_api_verified_at: Time.current, shopify_api_error_code: nil)
    end

    def refresh_token!
      unless @connection.shopify_refresh_token.present? &&
          @connection.shopify_refresh_token_expires_at.present? &&
          @connection.shopify_refresh_token_expires_at > Time.current
        raise Error.new("credentials_missing")
      end

      exchange_token!(grant_type: "refresh_token", refresh_token: @connection.shopify_refresh_token)
    end

    def exchange_token!(parameters)
      uri = URI("https://#{@connection.external_domain}/admin/oauth/access_token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(parameters.merge(client_id: ENV.fetch("SHOPIFY_CLIENT_ID"),
        client_secret: ENV.fetch("SHOPIFY_CLIENT_SECRET")))
      data = request_json(uri, request, token_request: true)
      token = data["access_token"]
      expires_in = data["expires_in"]
      refresh_token = data["refresh_token"]
      refresh_expires_in = data["refresh_token_expires_in"]
      unless valid_token?(token) && valid_token?(refresh_token) &&
          expires_in.is_a?(Integer) && expires_in.between?(61, 3600) &&
          refresh_expires_in.is_a?(Integer) && refresh_expires_in.between?(1, 90.days.to_i)
        raise Error.new("invalid_response")
      end
      # Persist only after identity and permission verification succeeds.
      @connection.shopify_access_token = token
      @connection.shopify_access_token_expires_at = Time.current + expires_in.seconds
      @connection.shopify_refresh_token = refresh_token
      @connection.shopify_refresh_token_expires_at = Time.current + refresh_expires_in.seconds
    end

    def valid_token?(token)
      token.is_a?(String) && token.present? && token.bytesize <= 8192 && !token.match?(/[\r\n]/)
    end

    def graphql_data(query:, variables:)
      uri = URI("https://#{@connection.external_domain}/admin/api/#{API_VERSION}/graphql.json")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Shopify-Access-Token"] = @connection.shopify_access_token
      request.body = JSON.generate(query: query, variables: variables)
      payload = request_json(uri, request)
      if payload["errors"].present?
        errors = payload["errors"]
        codes = errors.is_a?(Array) ? errors.filter_map { |entry| entry.is_a?(Hash) && entry["extensions"].is_a?(Hash) ? entry["extensions"]["code"] : nil } : []
        raise Error.new("rate_limited") if codes.include?("THROTTLED")
        raise Error.new("missing_scopes") if codes.include?("ACCESS_DENIED")

        raise Error.new("invalid_response")
      end
      raise Error.new("invalid_response") unless payload["data"].is_a?(Hash)

      payload.fetch("data")
    end

    def request_json(uri, request, token_request: false)
      status, body = if @transport
        response = @transport.call(uri, request)
        [ response.code.to_i, response.body.to_s ]
      else
        perform_request(uri, request)
      end
      raise Error.new("invalid_response") if body.bytesize > MAX_BODY_BYTES
      raise Error.new("rate_limited") if status == 429
      if token_request && status == 400
        error_payload = JSON.parse(body)
        error = error_payload.is_a?(Hash) ? error_payload["error"] : nil
        if error.is_a?(String) && error.match?(/\bshop_not_permitted\b/)
          raise Error.new("shop_not_permitted")
        end
      end
      raise Error.new("invalid_credentials") if status == 401 || (token_request && status == 400)
      raise Error.new("shop_not_permitted") if status == 403
      raise Error.new("unavailable") if status >= 500
      raise Error.new("invalid_response") unless status.between?(200, 299)

      data = JSON.parse(body)
      raise Error.new("invalid_response") unless data.is_a?(Hash)

      data
    rescue JSON::ParserError, EncodingError
      raise Error.new("invalid_response")
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      raise Error.new("unavailable")
    end

    def perform_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      http.write_timeout = 10
      http.max_retries = 0
      body = +""
      status = nil
      http.start do |session|
        session.request(request) do |response|
          status = response.code.to_i
          response.read_body do |chunk|
            raise Error.new("invalid_response") if body.bytesize + chunk.bytesize > MAX_BODY_BYTES

            body << chunk
          end
        end
      end
      [ status, body ]
    end
  end
end
