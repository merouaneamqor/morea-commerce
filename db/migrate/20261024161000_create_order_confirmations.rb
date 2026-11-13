class CreateOrderConfirmations < ActiveRecord::Migration[8.1]
  def change
    create_table :order_confirmations do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :order, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :assigned_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :claimed_at
      t.string :disposition, null: false, default: "pending"
      t.datetime :callback_at
      t.timestamps
    end
    add_index :order_confirmations, [ :store_id, :disposition, :callback_at ], name: "index_confirmation_queue"
    add_check_constraint :order_confirmations, "disposition IN ('pending', 'no_answer', 'callback', 'confirmed', 'cancelled')", name: "confirmation_disposition"

    create_table :confirmation_attempts do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :order_confirmation, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :actor_label, null: false
      t.string :outcome, null: false
      t.text :notes
      t.datetime :callback_at
      t.timestamps
    end
    add_check_constraint :confirmation_attempts, "outcome IN ('no_answer', 'callback', 'confirmed', 'cancelled')", name: "confirmation_attempt_outcome"
  end
end
