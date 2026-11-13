module Connections
  class SealloEntitlement
    # Shopify remains authoritative. A short cache lets signed order deliveries
    # proceed without a network call and bounds access after a plan cancellation.
    CACHE_LIFETIME = 15.minutes
    PLANS = { "Seallo Basic" => 30, "Seallo Pro" => 100, "Seallo Premium" => nil }.freeze

    def self.refresh!(connection)
      return unless connection.shopify_app == "seallo_connect"

      data = SealloBridge.entitlement(shop: connection.external_domain)
      connection.with_lock do
        attributes = attributes_for(data)
        unless attributes
          connection.update!(shopify_entitled_until: nil)
          return false
        end
        connection.update!(attributes)
      end
      true
    end

    # Share strict billing validation with read-only platform diagnostics.
    # Parsing never creates a connection or authorizes a workspace.
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
