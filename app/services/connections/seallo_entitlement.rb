module Connections
  class SealloEntitlement
    # Shopify remains authoritative. A short cache lets signed order deliveries
    # proceed without a network call and bounds access after a plan cancellation.
    CACHE_LIFETIME = 15.minutes
    PLANS = { "Seallo Basic" => 19, "Seallo Pro" => 99, "Seallo Premium" => nil }.freeze

    def self.refresh!(connection)
      return unless connection.shopify_app == "seallo_connect"

      data = SealloBridge.entitlement(shop: connection.external_domain)
      connection.with_lock do
        unless data["active"] == true
          connection.update!(shopify_entitled_until: nil)
          return false
        end
        start_time = Time.iso8601(data.fetch("current_period_start"))
        end_time = Time.iso8601(data.fetch("current_period_end"))
        name = data.fetch("plan_name")
        unless PLANS.key?(name) && data["order_limit"] == PLANS[name] && start_time <= Time.current && end_time.future? && end_time > start_time
          raise SealloBridge::Error, "invalid_response"
        end
        connection.update!(shopify_plan_name: name, shopify_order_limit: PLANS[name],
          shopify_billing_period_start: start_time, shopify_billing_period_end: end_time,
          shopify_entitled_until: [ CACHE_LIFETIME.from_now, end_time ].min)
      end
      true
    rescue ArgumentError, KeyError, TypeError
      raise SealloBridge::Error, "invalid_response"
    end
  end
end
