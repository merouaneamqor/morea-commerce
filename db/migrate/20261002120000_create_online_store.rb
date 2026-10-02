# frozen_string_literal: true

class CreateOnlineStore < ActiveRecord::Migration[8.1]
  def change
    create_table :home_sections do |t|
      t.references :store, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :home_sections, %i[store_id position]

    create_table :home_section_translations do |t|
      t.references :home_section, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :heading
      t.string :subheading
      t.text :body
      t.string :button_label
      t.timestamps
    end
    add_index :home_section_translations, %i[home_section_id locale], unique: true

    create_table :pages do |t|
      t.references :store, null: false, foreign_key: true
      t.string :slug, null: false
      t.boolean :published, null: false, default: true
      t.timestamps
    end
    add_index :pages, %i[store_id slug], unique: true

    create_table :page_translations do |t|
      t.references :page, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title
      t.text :body
      t.string :seo_title
      t.string :seo_description
      t.timestamps
    end
    add_index :page_translations, %i[page_id locale], unique: true

    create_table :menu_items do |t|
      t.references :store, null: false, foreign_key: true
      t.string :menu, null: false
      t.integer :position, null: false, default: 0
      t.string :link, null: false
      t.timestamps
    end
    add_index :menu_items, %i[store_id menu position]

    create_table :menu_item_translations do |t|
      t.references :menu_item, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :label
      t.timestamps
    end
    add_index :menu_item_translations, %i[menu_item_id locale], unique: true

    add_column :store_translations, :announcement, :string
  end
end
