class AddShopifyOrderSyncToStoreConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :store_connections, :shopify_orders_synced_at, :datetime
    add_column :store_connections, :shopify_webhook_checked_at, :datetime
  end
end
