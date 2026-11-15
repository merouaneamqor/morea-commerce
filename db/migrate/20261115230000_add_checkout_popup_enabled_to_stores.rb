# frozen_string_literal: true

# Storefront checkout UI: popup modal (default, from #335) vs previous on-page form.
class AddCheckoutPopupEnabledToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :checkout_popup_enabled, :boolean, default: true, null: false
  end
end
