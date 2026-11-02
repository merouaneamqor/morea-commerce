class AddSealloUninstallEventKey < ActiveRecord::Migration[8.1]
  def change
    add_column :store_connections, :shopify_uninstall_event_key, :string
  end
end
