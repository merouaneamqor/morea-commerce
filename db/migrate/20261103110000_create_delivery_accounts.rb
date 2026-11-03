# A merchant's accounts at delivery companies (Sendit, Ozon Express, Cathedis...), as on seallo.
# A workspace can have several accounts at the same company (for example two pickup cities).
class CreateDeliveryAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_accounts do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, limit: 30, null: false
      t.string :name, null: false
      t.string :code, limit: 12, null: false
      t.text :credentials_ciphertext
      t.string :contact_name
      t.string :contact_phone, limit: 30
      t.string :account_type, limit: 20, null: false, default: "normal"
      t.string :pickup_city, limit: 120
      t.boolean :allow_open, null: false, default: true
      t.decimal :delivery_fee, precision: 10, scale: 2
      t.decimal :return_fee, precision: 10, scale: 2
      t.boolean :is_active, null: false, default: true
      t.datetime :connected_at
      t.timestamps
    end

    add_index :delivery_accounts, %i[store_id code], unique: true
    add_check_constraint :delivery_accounts, "account_type IN ('normal', 'premium')", name: "delivery_accounts_account_type_known"
    add_check_constraint :delivery_accounts, "delivery_fee IS NULL OR delivery_fee >= 0", name: "delivery_accounts_delivery_fee_non_negative"
    add_check_constraint :delivery_accounts, "return_fee IS NULL OR return_fee >= 0", name: "delivery_accounts_return_fee_non_negative"
  end
end
