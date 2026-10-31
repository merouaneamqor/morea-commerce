# frozen_string_literal: true

module Connections
  # Erases buyer contact details from one imported order. Shared by Shopify privacy
  # requests and the time-based retention job so both apply identical rules.
  module OrderRedaction
    module_function

    def call(order)
      # Preserve financial amounts, inventory, provider identity and shipping state.
      # Free text may contain copied contact details, so erase it with snapshots.
      order.update_columns(customer_name: "Redacted", customer_phone: "redacted-#{order.id}", customer_city: "Redacted",
        customer_address: "Redacted", customer_district: nil, notes: nil, cancel_reason: nil,
        sendit_district_name: nil, sendit_message: nil, sendit_error: nil, tags: nil, updated_at: Time.current)
      order.order_events.update_all(body: "[Redacted]")
      order.order_confirmation&.confirmation_attempts&.update_all(notes: nil)
    end
  end
end
