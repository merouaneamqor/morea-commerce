class AddAgentPay < ActiveRecord::Migration[8.1]
  # Guarded so a database that already has part of this change (for example a
  # column added outside the migration history) can still record the version.
  def up
    unless column_exists?(:users, :pay_per_delivery_cents)
      add_column :users, :pay_per_delivery_cents, :integer, null: false, default: 0
    end
    unless check_constraint_exists?(:users, name: "users_pay_per_delivery_nonnegative")
      add_check_constraint :users, "pay_per_delivery_cents >= 0", name: "users_pay_per_delivery_nonnegative"
    end

    unless table_exists?(:agent_payments)
      create_table :agent_payments do |t|
        t.references :store, null: false, foreign_key: true
        t.references :user, null: false, foreign_key: true
        t.references :paid_by, foreign_key: { to_table: :users }
        t.bigint :amount_cents, null: false
        t.datetime :paid_at, null: false
        t.timestamps
      end
    end
    unless check_constraint_exists?(:agent_payments, name: "agent_payments_amount_positive")
      add_check_constraint :agent_payments, "amount_cents > 0", name: "agent_payments_amount_positive"
    end
    unless index_name_exists?(:agent_payments, "index_agent_payments_on_store_id_and_user_id_and_paid_at")
      add_index :agent_payments, %i[store_id user_id paid_at]
    end
  end

  def down
    drop_table :agent_payments, if_exists: true
    remove_check_constraint :users, name: "users_pay_per_delivery_nonnegative", if_exists: true
    remove_column :users, :pay_per_delivery_cents, if_exists: true
  end
end
