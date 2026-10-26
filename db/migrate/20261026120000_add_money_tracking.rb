class AddMoneyTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :cost_cents, :integer
    add_column :order_items, :unit_cost_cents, :integer
    add_column :orders, :collected_cents, :integer
    add_column :orders, :collected_at, :datetime
    add_column :orders, :refunded_cents, :integer, null: false, default: 0
    add_check_constraint :products, "cost_cents IS NULL OR cost_cents >= 0", name: "products_cost_cents_nonnegative"
    add_check_constraint :order_items, "unit_cost_cents IS NULL OR unit_cost_cents >= 0", name: "order_items_unit_cost_cents_nonnegative"
    add_check_constraint :orders, "collected_cents IS NULL OR collected_cents >= 0", name: "orders_collected_cents_nonnegative"
    add_check_constraint :orders, "refunded_cents >= 0", name: "orders_refunded_cents_nonnegative"

    create_table :store_expenses do |t|
      t.references :store, null: false, foreign_key: true
      t.date :spent_on, null: false
      t.string :category, null: false
      t.string :note
      t.bigint :amount_cents, null: false
      t.timestamps
    end
    add_index :store_expenses, [ :store_id, :spent_on ]
    add_check_constraint :store_expenses, "amount_cents > 0", name: "store_expenses_amount_positive"
  end
end
