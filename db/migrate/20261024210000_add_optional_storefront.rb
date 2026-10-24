# frozen_string_literal: true

class AddOptionalStorefront < ActiveRecord::Migration[8.0]
  def change
    # Existing tenants keep serving their public storefronts.
    add_column :stores, :storefront_enabled, :boolean, null: false, default: true
    add_column :access_requests, :storefront_enabled, :boolean, null: false, default: true
  end
end
