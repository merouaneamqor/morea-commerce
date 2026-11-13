# frozen_string_literal: true

class CreateStorefrontThemes < ActiveRecord::Migration[8.0]
  def change
    create_table :storefront_themes do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :catalog_key, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :published_at

      t.timestamps
    end

    add_check_constraint :storefront_themes,
      "status IN ('draft', 'published')",
      name: "storefront_themes_status"
    add_index :storefront_themes, [ :store_id, :status ],
      unique: true,
      where: "status = 'published'",
      name: "index_storefront_themes_one_published_per_store"
    add_index :storefront_themes, [ :store_id, :created_at ]
  end
end
