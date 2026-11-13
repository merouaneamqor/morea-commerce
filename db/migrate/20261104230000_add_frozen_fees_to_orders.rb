# frozen_string_literal: true

# The delivery fee and the return fee, frozen on the order when it is delivered or returned, as whole
# centimes. Accounting reads these, never the carrier's live fee, so a later change cannot rewrite old months.
# NULL means "not known at the time" and is counted as 0 with a warning, never guessed.
class AddFrozenFeesToOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :orders, :delivery_fee_cents, :integer
    add_column :orders, :return_fee_cents, :integer
    add_check_constraint :orders, "delivery_fee_cents IS NULL OR delivery_fee_cents >= 0", name: "orders_delivery_fee_cents_nonnegative"
    add_check_constraint :orders, "return_fee_cents IS NULL OR return_fee_cents >= 0", name: "orders_return_fee_cents_nonnegative"

    # Existing orders: the carrier fee recorded so far is the fee of the parcel that was delivered or returned.
    execute "UPDATE orders SET delivery_fee_cents = ROUND(sendit_fee * 100)::integer WHERE status = 'delivered' AND sendit_fee IS NOT NULL"
    execute "UPDATE orders SET return_fee_cents = ROUND(sendit_fee * 100)::integer WHERE status = 'returned' AND sendit_fee IS NOT NULL"
  end

  def down
    remove_check_constraint :orders, name: "orders_return_fee_cents_nonnegative"
    remove_check_constraint :orders, name: "orders_delivery_fee_cents_nonnegative"
    remove_column :orders, :return_fee_cents
    remove_column :orders, :delivery_fee_cents
  end
end
