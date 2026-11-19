module Connections
  # Legacy Shopify App Pricing helpers. Seallo Connect no longer requires a
  # Shopify plan, trial, or order allowance. refresh! is a no-op success for
  # seallo_connect so older call sites and diagnostics stay safe without
  # contacting the paired app for billing. Subscription-related columns are
  # left in place; this does not cancel live Shopify subscriptions.
  class SealloEntitlement
    CACHE_LIFETIME = 15.minutes
    PLANS = { "Seallo Basic" => 30, "Seallo Pro" => 100, "Seallo Premium" => nil }.freeze

    def self.refresh!(connection)
      return unless connection.shopify_app == "seallo_connect"

      true
    end

    # Kept for specs/diagnostics that still parse historical Partner payloads.
    # New access paths must not require a Shopify plan.
    def self.attributes_for(data, now: Time.current)
      raise SealloBridge::Error, "invalid_response" unless data.is_a?(Hash)
      return unless data["active"] == true

      start_time = Time.iso8601(data.fetch("current_period_start"))
      end_value = data.fetch("current_period_end")
      end_time = end_value.nil? ? nil : Time.iso8601(end_value)
      name = data.fetch("plan_name")
      unless PLANS.key?(name) && data.fetch("order_limit") == PLANS[name] && start_time <= now &&
          (end_time.nil? || (end_time > now && end_time > start_time))
        raise SealloBridge::Error, "invalid_response"
      end
      { shopify_plan_name: name, shopify_order_limit: PLANS[name],
        shopify_billing_period_start: start_time, shopify_billing_period_end: end_time,
        shopify_entitled_until: [ now + CACHE_LIFETIME, end_time ].compact.min }
    rescue ArgumentError, KeyError, TypeError
      raise SealloBridge::Error, "invalid_response"
    end
  end
end
