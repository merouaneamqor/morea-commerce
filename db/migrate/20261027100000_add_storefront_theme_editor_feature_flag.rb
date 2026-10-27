# frozen_string_literal: true

class AddStorefrontThemeEditorFeatureFlag < ActiveRecord::Migration[8.0]
  def change
    add_column :stores, :storefront_theme_editor_enabled, :boolean, null: false, default: false
  end
end
