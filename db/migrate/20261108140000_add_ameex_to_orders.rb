# frozen_string_literal: true

class AddAmeexToOrders < ActiveRecord::Migration[8.0]
  def change
    change_table :orders, bulk: true do |t|
      t.string :ameex_code
      t.string :ameex_status
      t.integer :ameex_city_id
      t.string :ameex_city_name
      t.decimal :ameex_fee, precision: 10, scale: 2
      t.string :ameex_message
      t.text :ameex_error
      t.datetime :ameex_synced_at
    end

    add_index :orders, [ :store_id, :ameex_code ], unique: true, where: "(ameex_code IS NOT NULL)", name: "index_orders_on_store_id_and_ameex_code"
  end
end
