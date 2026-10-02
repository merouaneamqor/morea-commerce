# frozen_string_literal: true

class AddSenditReturnsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :sendit_return_status, :string
    add_column :orders, :returned_at, :datetime
  end
end
