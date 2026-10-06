# frozen_string_literal: true

class AddAdminControlFields < ActiveRecord::Migration[8.1]
  def change
    change_table :stores, bulk: true do |t|
      t.integer :shipping_cents, null: false, default: 0
      t.integer :free_shipping_threshold_cents
      t.boolean :sendit_allow_open, null: false, default: true
      t.boolean :sendit_allow_try, null: false, default: true
      t.integer :low_stock_threshold, null: false, default: 5
    end

    change_table :orders, bulk: true do |t|
      t.integer :discount_cents, null: false, default: 0
      t.string :discount_code
    end
  end
end
