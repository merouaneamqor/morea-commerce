class CreateStoreConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :store_connections do |t|
      t.references :store, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :name, null: false
      t.string :external_domain, null: false
      t.string :external_store_id
      t.string :token, null: false
      t.text :webhook_secret_ciphertext, null: false
      t.boolean :active, default: true, null: false
      t.datetime :verified_at
      t.datetime :last_received_at
      t.string :last_error_code
      t.timestamps
    end
    add_index :store_connections, :token, unique: true
    add_index :store_connections, %i[store_id provider external_domain], unique: true
    add_check_constraint :store_connections, "provider IN ('shopify', 'woocommerce', 'youcan')", name: "store_connection_provider"
  end
end
