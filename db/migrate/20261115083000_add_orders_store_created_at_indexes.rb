# frozen_string_literal: true

class AddOrdersStoreCreatedAtIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :orders, [ :store_id, :created_at ],
      name: "index_orders_on_store_id_and_created_at",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :orders, [ :store_id, :status, :created_at ],
      name: "index_orders_on_store_id_and_status_and_created_at",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
