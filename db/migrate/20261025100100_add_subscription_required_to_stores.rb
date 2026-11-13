class AddSubscriptionRequiredToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :subscription_required, :boolean, default: false, null: false
  end
end
