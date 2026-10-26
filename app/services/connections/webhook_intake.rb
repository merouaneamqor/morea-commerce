# frozen_string_literal: true

require "openssl"
require "base64"
require "uri"

module Connections
  class WebhookIntake
    class Error < StandardError
      attr_reader :status
      def initialize(code, status: 422)
        @status = status
        super(code)
      end
    end
    Result = Struct.new(:receipt, :replayed, keyword_init: true)
    MAX_BODY_BYTES = 1_048_576

    def initialize(connection:)
      # Own the instance: a rejected transaction must not leave the caller's
      # object dirty and prevent its next request from acquiring a row lock.
      @connection = StoreConnection.find(connection.id)
    end

    def call(body:, headers:)
      raise Error.new("payload_too_large", status: 413) if body.bytesize > MAX_BODY_BYTES
      @connection.with_lock do
        raise Error.new("disconnected", status: 410) unless @connection.active?
        authenticate!(body, headers)
        raise Error.new("subscription_required", status: 402) unless @connection.store.operational_access?
        @connection.update!(last_received_at: Time.current, verified_at: @connection.verified_at || Time.current)
        payload = JSON.parse(body)
        validate_origin!(payload, headers)
        persist(payload)
      end
    rescue JSON::ParserError
      raise Error, "invalid_json"
    rescue TypeError, NoMethodError
      raise Error, "invalid_payload"
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise Error.new("secret_unavailable", status: 503)
    end

    # Imports an order fetched through the authorized Shopify API. The caller has
    # already authenticated with Shopify, so there is no signature or topic to check.
    def import(payload)
      @connection.with_lock do
        raise Error.new("disconnected", status: 410) unless @connection.active?
        raise Error.new("subscription_required", status: 402) unless @connection.store.operational_access?
        @connection.update!(last_received_at: Time.current, verified_at: @connection.verified_at || Time.current)
        persist(payload)
      end
    rescue TypeError, NoMethodError
      raise Error, "invalid_payload"
    end

    private

    def persist(payload)
      data = @connection.provider == "youcan" ? payload["data"] : payload
      external_id = data.is_a?(Hash) ? data["id"].to_s : ""
      raise Error, "invalid_external_id" unless external_id.match?(/\A[a-zA-Z0-9_-]{1,255}\z/)
      receipt = @connection.external_order_receipts.find_or_initialize_by(external_id: external_id)
      return Result.new(receipt: receipt, replayed: true) if receipt.persisted? && receipt.status == "accepted"

      begin
        attrs = OrderNormalizer.new(@connection).call(payload)
        # Savepoint removes partial customer/order writes if a validated model
        # refuses a provider payload, while preserving a safe rejection receipt.
        ApplicationRecord.transaction(requires_new: true) do
          store = @connection.store
          # Match existing intake's lock order for customer identity updates.
          store.with_lock do
            customer = store.customers.find_or_initialize_by(phone: attrs[:customer_phone])
            customer.assign_attributes(name: attrs[:customer_name], city: attrs[:customer_city])
            customer.save!
            order = store.orders.create!(attrs.except(:lines).merge(customer: customer, payment_method: "cod", status: "new"))
            attrs[:lines].each { |line| order.order_items.create!(line) }
            customer.increment!(:orders_count)
            order.record_event!("created", body: "Order received from #{@connection.provider}")
            receipt.assign_attributes(order: order, status: "accepted", error_code: nil, received_at: Time.current)
            receipt.save!
          end
        end
        @connection.update!(last_error_code: nil)
      rescue OrderNormalizer::Error => error
        receipt.assign_attributes(status: "rejected", error_code: error.message, received_at: Time.current)
        receipt.save!
        @connection.update!(last_error_code: error.message)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RangeError
        receipt.reload if receipt.persisted?
        receipt.assign_attributes(order: nil, status: "rejected", error_code: "invalid_order", received_at: Time.current)
        receipt.save!
        @connection.update!(last_error_code: "invalid_order")
      end
      Result.new(receipt: receipt, replayed: false)
    end

    def authenticate!(body, headers)
      header = { "shopify" => "X-Shopify-Hmac-SHA256", "woocommerce" => "X-WC-Webhook-Signature", "youcan" => "X-YOUCAN-SIGNATURE" }.fetch(@connection.provider)
      # OAuth connections are signed by the shared app; legacy ones by their own secret.
      secret = @connection.shopify_api_configured? ? ENV["SHOPIFY_CLIENT_SECRET"].to_s : @connection.webhook_secret.to_s
      raise Error.new("secret_unavailable", status: 503) if secret.blank?
      digest = OpenSSL::HMAC.digest("sha256", secret, body)
      expected = @connection.provider == "youcan" ? digest.unpack1("H*") : Base64.strict_encode64(digest)
      given = headers[header].to_s
      raise Error.new("invalid_signature", status: 401) unless given.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, given)
    end

    def validate_origin!(payload, headers)
      raise Error, "invalid_payload" unless payload.is_a?(Hash)
      case @connection.provider
      when "shopify"
        raise Error, "unsupported_topic" unless headers["X-Shopify-Topic"] == "orders/create"
        raise Error.new("source_mismatch", status: 403) unless headers["X-Shopify-Shop-Domain"].to_s.downcase == @connection.external_domain
      when "woocommerce"
        raise Error, "unsupported_topic" unless headers["X-WC-Webhook-Topic"] == "order.created"
        source = URI.parse(headers["X-WC-Webhook-Source"].to_s)
        raise Error.new("source_mismatch", status: 403) unless source.scheme == "https" && source.host.to_s.downcase == @connection.external_domain
      when "youcan"
        raise Error, "unsupported_topic" unless payload["event_name"] == "order.created" && headers["X-YOUCAN-TOPIC"] == "order.created"
        raise Error.new("source_mismatch", status: 403) unless payload.dig("data", "store_id") == @connection.external_store_id
      end
    rescue URI::InvalidURIError
      raise Error.new("source_mismatch", status: 403)
    end
  end
end
