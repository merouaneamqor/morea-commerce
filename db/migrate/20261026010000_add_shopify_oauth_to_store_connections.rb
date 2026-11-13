# frozen_string_literal: true

class AddShopifyOauthToStoreConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :store_connections, :shopify_oauth, :boolean, default: false, null: false
    add_column :store_connections, :shopify_access_token_ciphertext, :text
    add_column :store_connections, :shopify_access_token_expires_at, :datetime
    add_column :store_connections, :shopify_refresh_token_ciphertext, :text
    add_column :store_connections, :shopify_refresh_token_expires_at, :datetime
    add_column :store_connections, :shopify_granted_scopes, :string, array: true, default: [], null: false
    add_column :store_connections, :shopify_api_verified_at, :datetime
    add_column :store_connections, :shopify_api_error_code, :string
    add_column :store_connections, :shopify_oauth_state_digest, :string
    add_column :store_connections, :shopify_oauth_state_expires_at, :datetime
    add_index :store_connections, :shopify_oauth_state_digest, unique: true
    change_column_null :store_connections, :webhook_secret_ciphertext, true
    add_check_constraint :store_connections,
      "provider = 'shopify' OR webhook_secret_ciphertext IS NOT NULL",
      name: "store_connection_webhook_credentials"
    add_check_constraint :store_connections,
      "NOT shopify_oauth OR provider = 'shopify'",
      name: "store_connection_shopify_oauth"
    add_check_constraint :store_connections,
      "shopify_access_token_ciphertext IS NULL OR (shopify_oauth AND shopify_access_token_expires_at IS NOT NULL)",
      name: "store_connection_shopify_token"
    add_check_constraint :store_connections,
      "shopify_refresh_token_ciphertext IS NULL OR (shopify_oauth AND shopify_refresh_token_expires_at IS NOT NULL)",
      name: "store_connection_shopify_refresh_token"
  end
end
