# frozen_string_literal: true

require "openssl"
require "base64"

module Connections
  class SealloWebhooks
    PRIVACY_TOPICS = %w[customers/data_request customers/redact shop/redact].freeze
    TOPICS = (PRIVACY_TOPICS + %w[orders/create app/uninstalled app/scopes_update]).freeze

    class Error < StandardError
      attr_reader :status

      def initialize(code, status: 422)
        @status = status
        super(code)
      end
    end

    def self.call(body:, headers:)
      raise Error.new("payload_too_large", status: 413) if body.bytesize > WebhookIntake::MAX_BODY_BYTES

      verify_relay!(body, headers)
      secret = ENV["SEALLO_SHOPIFY_CLIENT_SECRET"].to_s
      raise Error.new("secret_unavailable", status: 503) if secret.blank?

      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
      signature = headers["X-Shopify-Hmac-SHA256"].to_s
      unless signature.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        raise Error.new("invalid_signature", status: 401)
      end

      topic = headers["X-Shopify-Topic"].to_s
      shop = headers["X-Shopify-Shop-Domain"].to_s
      raise Error, "unsupported_topic" unless TOPICS.include?(topic)
      raise Error, "source_mismatch" unless shop.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/) && shop.bytesize <= 253

      payload = JSON.parse(body)
      raise Error, "invalid_payload" unless payload.is_a?(Hash)
      if PRIVACY_TOPICS.include?(topic)
        raise Error.new("source_mismatch", status: 403) unless payload["shop_domain"] == shop
      elsif topic == "app/uninstalled"
        raise Error.new("source_mismatch", status: 403) unless payload["myshopify_domain"] == shop
      end

      connection = StoreConnection.find_by(provider: "shopify", shopify_app: "seallo_connect", external_domain: shop)
      if PRIVACY_TOPICS.include?(topic)
        # The relay signature authenticates the delivery identity as well as its
        # topic and shop. Distinct uninstall/reinstall events can have identical
        # bodies, so body-only deduplication would suppress a future request.
        key = Digest::SHA256.hexdigest("#{topic}\n#{headers['X-Shopify-Webhook-Id']}\n#{body}")
        record = ShopifyPrivacyRequest.create_or_find_by!(event_key: key) do |request|
          request.assign_attributes(store_connection: connection, topic: topic,
            identifiers: privacy_identifiers(payload, topic))
        end
        ShopifyPrivacyRequestJob.perform_later(record.id) if record.status == "pending"
        return { status: "received" }
      end
      return { status: "unlinked" } unless connection

      case topic
      when "orders/create"
        return { status: "disconnected" } unless connection.active?

        result = WebhookIntake.new(connection: connection).call(body: body, headers: headers)
        { status: result.receipt.status, replayed: result.replayed, error: result.receipt.error_code }
      when "app/uninstalled"
        connection.with_lock do
          event_key = Digest::SHA256.hexdigest("#{topic}\n#{headers['X-Shopify-Webhook-Id']}\n#{body}")
          # Keep this marker when reconnecting: a delayed retry from the old
          # installation must not revoke the replacement installation's tokens.
          next if connection.shopify_uninstall_event_key == event_key

          connection.update!(active: false, shopify_access_token: nil, shopify_refresh_token: nil,
            shopify_access_token_expires_at: nil, shopify_refresh_token_expires_at: nil,
            shopify_api_verified_at: nil, shopify_granted_scopes: [], shopify_oauth_state_digest: nil,
            shopify_oauth_state_expires_at: nil, shopify_uninstall_event_key: event_key)
        end
        { status: "disconnected" }
      when "app/scopes_update"
        connection.with_lock { connection.update!(shopify_api_verified_at: nil) }
        ShopifyOrdersSyncJob.perform_later(connection.id) if connection.active?
        { status: "received" }
      end
    rescue JSON::ParserError
      raise Error, "invalid_json"
    end

    def self.privacy_identifiers(payload, topic)
      raise Error, "invalid_payload" if payload["customer"].present? && !payload["customer"].is_a?(Hash)
      raise Error, "invalid_payload" if payload["data_request"].present? && !payload["data_request"].is_a?(Hash)

      ids = topic == "customers/data_request" ? payload["orders_requested"] : payload["orders_to_redact"]
      raise Error, "invalid_payload" unless topic == "shop/redact" || ids.is_a?(Array)
      raise Error, "invalid_payload" if ids && (ids.length > 10_000 || ids.any? { |id| !id.to_s.match?(/\A\d{1,30}\z/) })

      # No phone, email, address or full provider payload is persisted.
      { "shop_domain" => payload["shop_domain"], "order_ids" => Array(ids).map(&:to_s).uniq,
        "customer_id" => payload.dig("customer", "id").to_s.presence,
        "request_id" => payload.dig("data_request", "id").to_s.presence }.compact
    end

    def self.verify_relay!(body, headers)
      secret = ENV["SEALLO_BRIDGE_SECRET"].to_s
      raise Error.new("secret_unavailable", status: 503) if secret.blank?

      timestamp = headers["X-Seallo-Timestamp"].to_s
      webhook_id = headers["X-Shopify-Webhook-Id"].to_s
      signature = headers["X-Seallo-Webhook-Signature"].to_s
      unless timestamp.match?(/\A\d{1,12}\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300 &&
          webhook_id.match?(/\A[a-zA-Z0-9_-]{1,128}\z/) && signature.match?(/\A[0-9a-f]{64}\z/)
        raise Error.new("invalid_relay_signature", status: 401)
      end
      message = [ timestamp, headers["X-Shopify-Shop-Domain"].to_s, headers["X-Shopify-Topic"].to_s, webhook_id, body ].join("\n")
      expected = OpenSSL::HMAC.hexdigest("sha256", secret, message)
      raise Error.new("invalid_relay_signature", status: 401) unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end
    private_class_method :privacy_identifiers, :verify_relay!
  end
end
