class AddAgentPay < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pay_per_delivery_cents, :integer, null: false, default: 0
    add_check_constraint :users, "pay_per_delivery_cents >= 0", name: "users_pay_per_delivery_nonnegative"

    create_table :agent_payments do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :paid_by, foreign_key: { to_table: :users }
      t.bigint :amount_cents, null: false
      t.datetime :paid_at, null: false
      t.timestamps
    end
    add_check_constraint :agent_payments, "amount_cents > 0", name: "agent_payments_amount_positive"
    add_index :agent_payments, %i[store_id user_id paid_at]
  end
end
