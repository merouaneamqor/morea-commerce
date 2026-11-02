# frozen_string_literal: true

require "openssl"
require "base64"

module Connections
  class ShopifyLifecycle
    MAX_BODY_BYTES = 65_536
    SHOP_DOMAIN = /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/

    class Error < StandardError
      attr_reader :status

      def initialize(code, status:)
        @status = status
        super(code)
      end
    end

    def self.uninstall!(body:, headers:)
      raise Error.new("payload_too_large", status: 413) if body.bytesize > MAX_BODY_BYTES

      secret = ENV["SHOPIFY_CLIENT_SECRET"].to_s
      raise Error.new("secret_unavailable", status: 503) if secret.blank?

      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
      signature = headers["X-Shopify-Hmac-SHA256"].to_s
      unless signature.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        raise Error.new("invalid_signature", status: 401)
      end
      raise Error.new("unsupported_topic", status: 422) unless headers["X-Shopify-Topic"] == "app/uninstalled"

      shop = headers["X-Shopify-Shop-Domain"].to_s
      payload = JSON.parse(body)
      unless shop.match?(SHOP_DOMAIN) && payload.is_a?(Hash) && payload["myshopify_domain"] == shop
        raise Error.new("source_mismatch", status: 403)
      end

      StoreConnection.where(provider: "shopify", shopify_oauth: true, shopify_app: nil, external_domain: shop).find_each do |connection|
        connection.with_lock do
          connection.update!(active: false, shopify_access_token: nil, shopify_refresh_token: nil,
            shopify_access_token_expires_at: nil, shopify_refresh_token_expires_at: nil,
            shopify_api_verified_at: nil, shopify_api_error_code: nil, shopify_granted_scopes: [],
            shopify_oauth_state_digest: nil, shopify_oauth_state_expires_at: nil,
            shopify_webhook_checked_at: nil)
        end
      end
      true
    rescue JSON::ParserError, ArgumentError, TypeError
      raise Error.new("invalid_payload", status: 422)
    end
  end
end
