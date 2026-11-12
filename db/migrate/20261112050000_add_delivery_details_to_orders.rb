# frozen_string_literal: true

# Details typed when an order is created by hand.
# - delivery_provider: the delivery company chosen for the order (one the store is connected to).
# - scheduled_for: the day and time the customer wants the order.
# - advance_cents: money already paid by the customer (an advance), in whole centimes: what is left to collect is the total minus it.
class AddDeliveryDetailsToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :delivery_provider, :string, limit: 30
    add_column :orders, :scheduled_for, :datetime
    add_column :orders, :advance_cents, :integer, default: 0, null: false
    add_check_constraint :orders, "advance_cents >= 0", name: "orders_advance_cents_nonnegative"
  end
end
