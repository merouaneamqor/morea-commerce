# frozen_string_literal: true

class AddOzonToOrders < ActiveRecord::Migration[8.0]
  def change
    change_table :orders, bulk: true do |t|
      t.string :ozon_code
      t.string :ozon_status
      t.integer :ozon_city_id
      t.string :ozon_city_name
      t.decimal :ozon_fee, precision: 10, scale: 2
      t.string :ozon_message
      t.text :ozon_error
      t.datetime :ozon_synced_at
    end

    add_index :orders, [ :store_id, :ozon_code ], unique: true, where: "(ozon_code IS NOT NULL)", name: "index_orders_on_store_id_and_ozon_code"
  end
end
