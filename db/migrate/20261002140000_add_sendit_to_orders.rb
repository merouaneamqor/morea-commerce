# frozen_string_literal: true

class AddSenditToOrders < ActiveRecord::Migration[8.1]
  def change
    change_table :orders, bulk: true do |t|
      t.string :sendit_code
      t.string :sendit_status
      t.integer :sendit_district_id
      t.string :sendit_district_name
      t.decimal :sendit_fee, precision: 10, scale: 2
      t.string :sendit_message
      t.date :sendit_deliver_by
      t.text :sendit_error
      t.datetime :sendit_synced_at
    end
    add_index :orders, :sendit_code, unique: true
  end
end
