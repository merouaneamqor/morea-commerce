# frozen_string_literal: true

module Platform
  # Explicit platform-support checks. This service never links a shop or imports orders.
  class SealloDiagnostics
    MESSAGES = {
      "verified" => "The connection and Shopify order access are verified.",
      "entitlement_verified" => "Shopify returned a valid plan. The merchant can retry connecting from Seallo Connect.",
      "disconnected" => "This connection is disconnected. The merchant must approve reconnection in Shopify through Seallo Connect.",
      "not_entitled" => "No active Shopify plan was returned. Check the plan in Seallo Connect before retrying.",
      "authorization_expired" => "This authorization link expired. The merchant must start a new connection from Seallo Connect.",
      "authorization_consumed" => "This authorization link was already used. Check the existing connection instead.",
      "unsupported_connection" => "Only Seallo Connect Shopify connections can be checked here.",
      "config_missing" => "The Seallo bridge configuration needs attention from the platform operator.",
      "credentials_missing" => "Shopify authorization is missing. The merchant must reconnect through Seallo Connect.",
      "invalid_credentials" => "Shopify authorization is no longer valid. The merchant must reconnect through Seallo Connect.",
      "shop_not_permitted" => "Shopify has not permitted this store to connect. Check app access in Shopify.",
      "missing_scopes" => "Shopify order access is missing. Check app permissions and protected customer data access in Seallo Connect.",
      "source_mismatch" => "The stored Shopify identity could not be verified. Check the store in Seallo Connect.",
      "rate_limited" => "Shopify or Seallo temporarily limited requests. Retry later.",
      "unavailable" => "Shopify or Seallo could not be reached. Retry later.",
      "invalid_response" => "Seallo returned an incomplete or unsupported response. Check the deployed bridge and plan contract, then retry."
    }.freeze

    Result = Struct.new(:code, :plan_name, :order_limit, :period_end, keyword_init: true) do
      def success?
        %w[verified entitlement_verified].include?(code)
      end

      def message
        MESSAGES.fetch(code)
      end
    end

    def initialize(actor:)
      @actor = actor
    end

    def recheck(connection:)
      authorize!
      return result("unsupported_connection") unless connection.is_a?(StoreConnection) && connection.persisted?

      connection.reload
      unless connection.provider == "shopify" && connection.shopify_app == "seallo_connect" && connection.shopify_oauth?
        return result("unsupported_connection")
      end
      return result("disconnected") unless connection.active?
      return result("not_entitled") unless Connections::SealloEntitlement.refresh!(connection)

      Connections::ShopifyApi.new(connection: connection).verify!
      result("verified", plan_name: connection.shopify_plan_name, order_limit: connection.shopify_order_limit,
        period_end: connection.shopify_billing_period_end)
    rescue Connections::SealloBridge::Error => error
      result(safe_code(error.message))
    rescue Connections::ShopifyApi::Error => error
      result(safe_code(error.code))
    end

    def diagnose_link(authorization:)
      authorize!
      raise ActiveRecord::RecordNotFound unless authorization.is_a?(SealloConnectionCode) && authorization.persisted?
      authorization.reload
      return result("authorization_consumed") if authorization.consumed_at.present?
      return result("authorization_expired") unless authorization.expires_at&.future?

      domain = authorization.shop_domain.to_s
      return result("source_mismatch") unless domain.bytesize <= 253 && domain.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)

      attributes = Connections::SealloEntitlement.attributes_for(Connections::SealloBridge.entitlement(shop: domain))
      return result("not_entitled") unless attributes

      result("entitlement_verified", plan_name: attributes.fetch(:shopify_plan_name),
        order_limit: attributes.fetch(:shopify_order_limit), period_end: attributes.fetch(:shopify_billing_period_end))
    rescue Connections::SealloBridge::Error => error
      result(safe_code(error.message))
    end

    private

    def authorize!
      raise ActiveRecord::RecordNotFound unless @actor.is_a?(User) && @actor.persisted?
      @actor.reload
      raise ActiveRecord::RecordNotFound unless @actor.active? && @actor.super_admin?
    end

    def safe_code(code)
      Connections::ShopifyApi::Error::CODES.include?(code) ? code : "invalid_response"
    end

    def result(code, **metadata)
      Result.new(code: code, **metadata)
    end
  end
end
