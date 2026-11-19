module Connections
  class SealloEntitlement
    # Seallo workspace billing is authoritative. A short cache lets signed order
    # deliveries proceed without a network call and bounds access after cancellation.
    # Shopify App Pricing remains a temporary fallback for shops that still have an
    # active Shopify contract after public plans were removed.
    CACHE_LIFETIME = 15.minutes
    SHOPIFY_LEGACY_PLANS = { "Seallo Basic" => 30, "Seallo Pro" => 100, "Seallo Premium" => nil }.freeze
    # Kept as PLANS for callers/specs that still validate the Shopify-legacy contract.
    PLANS = SHOPIFY_LEGACY_PLANS

    def self.refresh!(connection)
      return unless connection.shopify_app == "seallo_connect"

      connection.with_lock do
        if (attributes = attributes_from_store(connection.store))
          connection.update!(attributes)
          return true
        end

        data = SealloBridge.entitlement(shop: connection.external_domain)
        attributes = attributes_for(data)
        unless attributes
          connection.update!(shopify_entitled_until: nil)
          return false
        end
        connection.update!(attributes)
      end
      true
    end

    # Authoritative Seallo workspace subscription. Never trusts a browser or shop
    # parameter: the connection's store row is the only workspace identity used.
    def self.attributes_from_store(store, now: Time.current)
      return unless store.is_a?(Store) && store.seallo_subscription_access?

      if store.plan.present?
        config = Plans.plan(store.plan)
        return unless config

        order_limit = config["orders"]
        return if order_limit && (!order_limit.is_a?(Integer) || order_limit <= 0)

        start_time, end_time = period_for(store, now)
        return unless start_time && start_time <= now && (end_time.nil? || (end_time > now && end_time > start_time))

        cache_attributes(
          plan_name: config.fetch("name"),
          order_limit: order_limit,
          start_time: start_time,
          end_time: end_time,
          now: now
        )
      else
        # Legacy workspaces that predate plans keep access without inventing a quota.
        cache_attributes(plan_name: nil, order_limit: nil, start_time: now, end_time: nil, now: now)
      end
    end

    # Shopify-legacy Partner/Admin contract. Used only when Seallo billing does not
    # grant access. Parsing never creates a connection or authorizes a workspace.
    def self.attributes_for(data, now: Time.current)
      raise SealloBridge::Error, "invalid_response" unless data.is_a?(Hash)
      return unless data["active"] == true

      start_time = Time.iso8601(data.fetch("current_period_start"))
      end_value = data.fetch("current_period_end")
      end_time = end_value.nil? ? nil : Time.iso8601(end_value)
      name = data.fetch("plan_name")
      unless SHOPIFY_LEGACY_PLANS.key?(name) && data.fetch("order_limit") == SHOPIFY_LEGACY_PLANS[name] && start_time <= now &&
          (end_time.nil? || (end_time > now && end_time > start_time))
        raise SealloBridge::Error, "invalid_response"
      end
      cache_attributes(
        plan_name: name,
        order_limit: SHOPIFY_LEGACY_PLANS[name],
        start_time: start_time,
        end_time: end_time,
        now: now
      )
    rescue ArgumentError, KeyError, TypeError
      raise SealloBridge::Error, "invalid_response"
    end

    def self.present(connection)
      {
        "active" => connection.shopify_entitled_until.present? && connection.shopify_entitled_until > Time.current,
        "current_period_start" => connection.shopify_billing_period_start&.iso8601,
        "current_period_end" => connection.shopify_billing_period_end&.iso8601,
        "plan_name" => connection.shopify_plan_name,
        "plan_handle" => plan_handle_for(connection.shopify_plan_name, connection.store.plan),
        "order_limit" => connection.shopify_order_limit
      }
    end

    def self.inactive_payload
      {
        "active" => false,
        "current_period_start" => nil,
        "current_period_end" => nil,
        "plan_name" => nil,
        "plan_handle" => nil,
        "order_limit" => nil
      }
    end

    def self.cache_attributes(plan_name:, order_limit:, start_time:, end_time:, now:)
      {
        shopify_plan_name: plan_name,
        shopify_order_limit: order_limit,
        shopify_billing_period_start: start_time,
        shopify_billing_period_end: end_time,
        shopify_entitled_until: [ now + CACHE_LIFETIME, end_time ].compact.min
      }
    end
    private_class_method :cache_attributes

    def self.period_for(store, now)
      if store.trial_active?
        end_time = store.trial_ends_at
        [ end_time - Plans.trial_days.days, end_time ]
      elsif store.billing_status == "active" && store.billing_period_ends_on.present? && store.billing_period_ends_on >= Date.current
        end_time = store.billing_period_ends_on.in_time_zone.end_of_day
        start_time = if store.billing_interval == "yearly"
          (store.billing_period_ends_on - 1.year + 1.day).in_time_zone.beginning_of_day
        else
          (store.billing_period_ends_on - 1.month + 1.day).in_time_zone.beginning_of_day
        end
        [ start_time, end_time ]
      elsif !store.subscription_required?
        [ now, nil ]
      end
    end
    private_class_method :period_for

    def self.plan_handle_for(plan_name, store_plan)
      return store_plan if store_plan.present? && Plans.plan?(store_plan) && Plans.plan(store_plan)["name"] == plan_name
      return plan_name.to_s.downcase.tr(" ", "-") if SHOPIFY_LEGACY_PLANS.key?(plan_name)

      nil
    end
    private_class_method :plan_handle_for
  end
end
