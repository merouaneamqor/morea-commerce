# frozen_string_literal: true

module Connections
  # The app verifies billing with Shopify and publishes a bounded entitlement.
  # Intake calls this under the connection lock, after accepted receipt replay.
  # Checking and creating the next accepted receipt therefore share one lock.
  class SealloAllowance
    def self.check!(connection)
      return unless connection.shopify_app == "seallo_connect"

      now = Time.current
      unless connection.shopify_entitled_until && connection.shopify_entitled_until > now &&
          connection.shopify_billing_period_start && connection.shopify_billing_period_start <= now &&
          connection.shopify_billing_period_end && connection.shopify_billing_period_end > now
        raise WebhookIntake::Error.new("subscription_required", status: 402)
      end

      limit = connection.shopify_order_limit
      return if limit.nil?
      raise WebhookIntake::Error.new("order_limit_reached", status: 429) if used(connection) >= limit
    end

    def self.used(connection)
      return 0 unless connection.shopify_app == "seallo_connect" &&
        connection.shopify_billing_period_start && connection.shopify_billing_period_end

      connection.external_order_receipts.where(status: "accepted",
        received_at: connection.shopify_billing_period_start...connection.shopify_billing_period_end).count
    end
  end
end
