class AddSealloConnect < ActiveRecord::Migration[8.1]
  def change
    add_column :store_connections, :shopify_app, :string
    add_index :store_connections, :external_domain, unique: true, where: "shopify_app = 'seallo_connect'", name: "unique_seallo_shop"
    add_check_constraint :store_connections, "shopify_app IS NULL OR (shopify_app = 'seallo_connect' AND provider = 'shopify' AND shopify_oauth)", name: "seallo_shopify_only"
    add_column :store_connections, :shopify_sync_state, :string
    add_column :store_connections, :shopify_sync_started_at, :datetime
    add_column :store_connections, :shopify_sync_finished_at, :datetime
    add_column :store_connections, :shopify_sync_counts, :jsonb, default: {}, null: false
    add_column :store_connections, :shopify_sync_error, :string
    create_table :seallo_connection_codes do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :seallo_connection_codes, :digest, unique: true
  end
end
