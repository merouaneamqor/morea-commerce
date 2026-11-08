# frozen_string_literal: true

# Which connected courier Seallo uses to create parcels on confirmation. The merchant chooses;
# only one account per store can be the default.
class AddShipsByDefaultToDeliveryAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :delivery_accounts, :ships_by_default, :boolean, null: false, default: false
    add_index :delivery_accounts, :store_id, unique: true, where: "ships_by_default", name: "index_delivery_accounts_one_default_per_store"
  end
end
