class CreateConfirmationShifts < ActiveRecord::Migration[8.1]
  def change
    create_table :confirmation_shifts do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :actor_label, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.timestamps
    end
    # One open shift per agent: a concurrent double clock-in fails in the database.
    add_index :confirmation_shifts, :user_id, unique: true, where: "ended_at IS NULL", name: "index_confirmation_shifts_one_open_per_user"
    add_index :confirmation_shifts, [ :store_id, :started_at ]
    add_check_constraint :confirmation_shifts, "ended_at IS NULL OR ended_at > started_at", name: "confirmation_shift_order"
  end
end
