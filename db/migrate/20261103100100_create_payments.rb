# Subscription payments declared by merchants (bank transfer today, card later); amounts are whole US dollars.
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.string :plan, null: false
      t.string :billing, null: false
      t.integer :amount, null: false
      t.string :currency, limit: 3, null: false, default: "USD"
      t.string :payment_method, null: false
      t.string :status, null: false, default: "pending"
      t.string :reference, limit: 100
      t.datetime :paid_at
      t.timestamps
    end

    add_check_constraint :payments, "billing IN ('monthly', 'annual')", name: "payments_billing_known"
    add_check_constraint :payments, "payment_method IN ('transfer', 'card')", name: "payments_method_known"
    add_check_constraint :payments, "status IN ('pending', 'paid', 'rejected')", name: "payments_status_known"
    add_check_constraint :payments, "amount >= 0", name: "payments_amount_non_negative"
    # One transfer waiting for verification per workspace; a new declaration updates it.
    add_index :payments, :store_id, unique: true, where: "status = 'pending' AND payment_method = 'transfer'", name: "index_payments_one_pending_transfer"
  end
end
