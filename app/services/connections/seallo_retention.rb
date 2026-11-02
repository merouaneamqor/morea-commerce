# frozen_string_literal: true

module Connections
  # Redacts buyer contact details on Seallo Connect imports once an order has been
  # completed for RETENTION. Matches the retention period published on the privacy
  # page. Only terminal orders are touched, and only orders imported through a
  # Seallo Connect connection; other providers' orders and active shipments keep
  # their data. Safe to run repeatedly.
  class SealloRetention
    RETENTION = 180.days
    COMPLETED_AT = "COALESCE(orders.delivered_at, orders.cancelled_at, orders.returned_at, orders.updated_at)"

    def self.call(now: Time.current)
      new(now: now).call
    end

    def initialize(now:)
      @cutoff = now - RETENTION
    end

    # Returns the number of orders redacted.
    def call
      redacted = 0
      StoreConnection.where(shopify_app: "seallo_connect").find_each do |connection|
        # Same lock order as intake and privacy requests: connection, then workspace.
        connection.with_lock do
          connection.store.with_lock do
            due(connection).find_each { |order| redacted += 1 if redact(order) }
          end
        end
      end
      redacted
    end

    private

    def due(connection)
      imported = connection.external_order_receipts.where(status: "accepted").select(:order_id)
      connection.store.orders.where(id: imported, status: ShopifyPrivacyRequest::TERMINAL_STATUSES)
        .where.not(customer_name: "Redacted").where("#{COMPLETED_AT} < ?", @cutoff)
    end

    def redact(order)
      order.with_lock do
        next false if order.customer_name == "Redacted" || !ShopifyPrivacyRequest::TERMINAL_STATUSES.include?(order.status)

        OrderRedaction.call(order)
        anonymize_profile(order.customer)
        true
      end
    end

    # A buyer profile is shared by every order of that buyer. Anonymize it only once
    # none of their orders still holds contact details (other providers included).
    def anonymize_profile(customer)
      return unless customer
      return if customer.orders.where.not(customer_name: "Redacted").exists?

      customer.update_columns(name: "Redacted", phone: "redacted-#{customer.id}", email: nil, city: nil, updated_at: Time.current)
      customer.addresses.delete_all
    end
  end
end
