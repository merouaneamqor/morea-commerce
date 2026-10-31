class AddSealloPollCursor < ActiveRecord::Migration[8.1]
  def change
    add_column :store_connections, :shopify_poll_cursor, :string
    add_column :store_connections, :shopify_poll_since, :datetime
    add_column :store_connections, :shopify_poll_until, :datetime
  end
end
