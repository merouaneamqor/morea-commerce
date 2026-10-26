# frozen_string_literal: true

module Connections
  # Brings Shopify COD orders into Morea for one OAuth-authorized connection.
  # New orders normally arrive through an app-registered `orders/create` webhook;
  # polling catches up on anything missed while the service was asleep or down.
  # Both paths feed the same receipt-backed intake, so an order is never imported twice.
  class ShopifyOrderSync
    FIRST_SYNC_DAYS = 7
    OVERLAP = 5.minutes
    PAGE_SIZE = 10
    MAX_PAGES = 20
    WEBHOOK_CHECK_INTERVAL = 1.day

    WEBHOOKS_QUERY = <<~GRAPHQL
      query { webhookSubscriptions(first: 25, topics: [ORDERS_CREATE]) { nodes { id endpoint { __typename ... on WebhookHttpEndpoint { callbackUrl } } } } }
    GRAPHQL
    WEBHOOK_CREATE = <<~GRAPHQL
      mutation($url: URL!) { webhookSubscriptionCreate(topic: ORDERS_CREATE, webhookSubscription: { callbackUrl: $url, format: JSON }) { webhookSubscription { id } userErrors { field message } } }
    GRAPHQL
    ORDERS_QUERY = <<~GRAPHQL
      query($first: Int!, $after: String, $query: String) {
        orders(first: $first, after: $after, query: $query, sortKey: CREATED_AT) {
          pageInfo { hasNextPage endCursor }
          nodes {
            legacyResourceId createdAt currencyCode phone cancelledAt
            displayFinancialStatus displayFulfillmentStatus paymentGatewayNames
            totalPriceSet { shopMoney { amount } }
            totalTaxSet { shopMoney { amount } }
            totalDiscountsSet { shopMoney { amount } }
            totalShippingPriceSet { shopMoney { amount } }
            shippingAddress { name phone city address1 address2 countryCodeV2 }
            lineItems(first: 50) { nodes { name quantity variantTitle requiresShipping unfulfilledQuantity
              originalUnitPriceSet { shopMoney { amount } } totalDiscountSet { shopMoney { amount } } } }
          }
        }
      }
    GRAPHQL

    Result = Struct.new(:imported, :rejected, :replayed, :complete, keyword_init: true)

    def self.webhook_url(connection)
      Rails.application.routes.url_helpers.store_orders_webhook_url(token: connection.token,
        host: Store.base_domain, protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
    end

    def initialize(connection, api: nil, now: Time.current)
      @connection = connection
      @api = api || ShopifyApi.new(connection: connection)
      @now = now
    end

    def call
      ensure_webhook!
      poll!
    end

    def ensure_webhook!
      checked = @connection.shopify_webhook_checked_at
      return if checked && checked > WEBHOOK_CHECK_INTERVAL.ago(@now)

      url = self.class.webhook_url(@connection)
      existing = @api.graphql(query: WEBHOOKS_QUERY).dig("webhookSubscriptions", "nodes").to_a
      registered = existing.any? { |node| node.dig("endpoint", "callbackUrl") == url }
      unless registered
        result = @api.graphql(query: WEBHOOK_CREATE, variables: { url: url }).fetch("webhookSubscriptionCreate")
        # "already taken" means another request registered the same address first.
        errors = Array(result["userErrors"]).reject { |error| error["message"].to_s.match?(/already|taken/i) }
        raise ShopifyApi::Error.new("invalid_response") if errors.any?
      end
      @connection.update_columns(shopify_webhook_checked_at: @now)
    end

    def poll!
      since = @connection.shopify_orders_synced_at || FIRST_SYNC_DAYS.days.ago(@now)
      filter = "created_at:>='#{(since - OVERLAP).utc.iso8601}' financial_status:pending fulfillment_status:unfulfilled"
      intake = WebhookIntake.new(connection: @connection)
      counts = Hash.new(0)
      cursor = nil
      last_seen = nil
      complete = false
      MAX_PAGES.times do
        page = @api.graphql(query: ORDERS_QUERY, variables: { first: PAGE_SIZE, after: cursor, query: filter }).fetch("orders")
        page.fetch("nodes").each do |node|
          result = intake.import(order_payload(node))
          counts[result.replayed ? :replayed : (result.receipt.status == "accepted" ? :imported : :rejected)] += 1
          last_seen = Time.iso8601(node["createdAt"]) if node["createdAt"].present?
        end
        cursor = page.dig("pageInfo", "endCursor")
        unless page.dig("pageInfo", "hasNextPage")
          complete = true
          break
        end
      end
      # A truncated run resumes from the last order it handled; a complete one from now.
      @connection.update_columns(shopify_orders_synced_at: complete ? @now : (last_seen || since))
      Result.new(imported: counts[:imported], rejected: counts[:rejected], replayed: counts[:replayed], complete: complete)
    end

    # Rebuild the shape of Shopify's order webhook so one normalizer owns every
    # acceptance rule (COD only, MAD only, no tax or discounts, unfulfilled).
    def order_payload(node)
      amount = ->(set) { set&.dig("shopMoney", "amount") }
      address = node["shippingAddress"]
      fulfillment = node["displayFulfillmentStatus"].to_s
      payload = {
        "id" => node.fetch("legacyResourceId").to_s,
        "currency" => node["currencyCode"],
        "total_price" => amount.call(node["totalPriceSet"]),
        "total_tax" => amount.call(node["totalTaxSet"]),
        "total_discounts" => amount.call(node["totalDiscountsSet"]),
        "total_shipping_price_set" => { "shop_money" => { "amount" => amount.call(node["totalShippingPriceSet"]) } },
        "financial_status" => node["displayFinancialStatus"].to_s.downcase,
        "payment_gateway_names" => node["paymentGatewayNames"],
        "cancelled_at" => node["cancelledAt"],
        "fulfillment_status" => fulfillment == "UNFULFILLED" ? nil : fulfillment.downcase.presence,
        "line_items" => node.dig("lineItems", "nodes").to_a.map do |line|
          {
            "name" => line["name"], "quantity" => line["quantity"],
            "price" => amount.call(line["originalUnitPriceSet"]), "variant_title" => line["variantTitle"],
            "total_discount" => amount.call(line["totalDiscountSet"]) || "0",
            "requires_shipping" => line["requiresShipping"],
            "fulfillment_status" => line["unfulfilledQuantity"].to_i < line["quantity"].to_i ? "partial" : nil
          }
        end
      }
      if address.is_a?(Hash)
        payload["shipping_address"] = { "name" => address["name"], "phone" => address["phone"].presence || node["phone"],
          "city" => address["city"], "address1" => address["address1"], "address2" => address["address2"],
          "country_code" => address["countryCodeV2"] }
      end
      payload
    end
  end
end
