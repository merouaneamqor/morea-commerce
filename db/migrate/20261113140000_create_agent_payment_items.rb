# The orders a payout settles, one row each, so the owner can pay an agent for the orders they pick and an order is never paid twice.
class CreateAgentPaymentItems < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_payment_items do |t|
      t.references :store, null: false, foreign_key: true
      t.references :agent_payment, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :amount_cents, null: false
      t.timestamps
    end
    add_check_constraint :agent_payment_items, "amount_cents > 0", name: "agent_payment_items_amount_positive"
  end
end
