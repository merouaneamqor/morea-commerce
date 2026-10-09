# frozen_string_literal: true

class AddBillingToStores < ActiveRecord::Migration[8.0]
  def change
    add_column :stores, :billing_interval, :string, null: false, default: "monthly"
    add_column :stores, :billing_status, :string, null: false, default: "active"
    add_column :stores, :billing_amount_cents, :integer, null: false, default: 0
    add_column :stores, :billing_period_ends_on, :date

    add_index :stores, :billing_interval
    add_index :stores, :billing_status
  end
end
