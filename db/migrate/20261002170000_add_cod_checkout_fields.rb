# frozen_string_literal: true

class AddCodCheckoutFields < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :customer_district, :string
    add_column :stores, :whatsapp, :string
  end
end
