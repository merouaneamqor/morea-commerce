class CreateRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :registrations do |t|
      t.string :business_name, null: false
      t.string :email, null: false
      t.string :password_digest
      t.string :locale, null: false, default: "fr"
      t.string :verification_nonce, null: false
      t.datetime :verification_sent_at
      t.datetime :verified_at
      t.references :user, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.timestamps
    end
    add_index :registrations, :email, unique: true
    add_check_constraint :registrations, "email = lower(email)", name: "registrations_normalized_email"
    add_check_constraint :registrations, "verified_at IS NOT NULL OR user_id IS NULL", name: "registrations_verification_identity"
    add_check_constraint :registrations, "verified_at IS NULL OR password_digest IS NOT NULL", name: "registrations_verified_password"
  end
end
