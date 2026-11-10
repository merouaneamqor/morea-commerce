# frozen_string_literal: true

class EnableStorefrontThemeEditorByDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :stores, :storefront_theme_editor_enabled, from: false, to: true
    # Existing published storefronts should see Themes after the editor stack shipped.
    execute <<~SQL.squish
      UPDATE stores
      SET storefront_theme_editor_enabled = TRUE
      WHERE storefront_enabled = TRUE
        AND storefront_theme_editor_enabled = FALSE
    SQL
  end

  def down
    change_column_default :stores, :storefront_theme_editor_enabled, from: true, to: false
  end
end
