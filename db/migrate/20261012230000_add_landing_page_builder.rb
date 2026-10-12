# frozen_string_literal: true

class AddLandingPageBuilder < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :template, :string, null: false, default: "content"
    add_index :pages, [ :store_id, :template ]

    create_table :page_sections do |t|
      t.references :page, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :position, default: 0, null: false
      t.boolean :visible, default: true, null: false
      t.jsonb :settings, default: {}, null: false
      t.timestamps
    end
    add_index :page_sections, [ :page_id, :position ]

    create_table :page_section_translations do |t|
      t.references :page_section, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :heading
      t.string :subheading
      t.text :body
      t.string :button_label
      t.timestamps
    end
    add_index :page_section_translations, [ :page_section_id, :locale ], unique: true,
              name: "index_page_section_translations_on_page_section_and_locale"
  end
end
