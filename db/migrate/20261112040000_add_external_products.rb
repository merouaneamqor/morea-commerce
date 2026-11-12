# frozen_string_literal: true

# Products imported from a connected store (Shopify, WooCommerce, YouCan).
# - products.store_connection_id / external_id: where the product comes from and its id there. The connection is
#   nullified (not cascaded) when it is deleted: the catalog an order refers to is never lost.
# - product_variants.external_id: the id of the variant at the source.
# - store_connections.api_credentials_ciphertext: the API keys of WooCommerce (consumer key and secret) and the access
#   token of YouCan, encrypted like the webhook secret. Shopify keeps using its OAuth tokens.
# - store_connections.products_sync_*: when the catalog was last imported, its state and what it did.
class AddExternalProducts < ActiveRecord::Migration[8.0]
  def change
    add_reference :products, :store_connection, foreign_key: { on_delete: :nullify }, index: true
    add_column :products, :external_id, :string
    add_column :products, :external_synced_at, :datetime
    add_index :products, %i[store_connection_id external_id], unique: true, where: "external_id IS NOT NULL", name: "index_products_on_connection_and_external_id"

    add_column :product_variants, :external_id, :string
    add_index :product_variants, %i[product_id external_id], unique: true, where: "external_id IS NOT NULL", name: "index_product_variants_on_product_and_external_id"

    add_column :store_connections, :api_credentials_ciphertext, :text
    add_column :store_connections, :products_sync_state, :string
    add_column :store_connections, :products_synced_at, :datetime
    add_column :store_connections, :products_sync_error, :string
    add_column :store_connections, :products_sync_counts, :jsonb, default: {}, null: false
  end
end
