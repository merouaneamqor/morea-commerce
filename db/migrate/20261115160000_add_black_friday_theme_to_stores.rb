# frozen_string_literal: true

class AddBlackFridayThemeToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :black_friday_theme, :boolean, default: false, null: false
  end
end
