# frozen_string_literal: true

class AddSenditPickupToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :sendit_pickup_district_id, :integer
  end
end
