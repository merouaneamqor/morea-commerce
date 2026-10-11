# frozen_string_literal: true

class CreateProductColorways < ActiveRecord::Migration[8.1]
  def change
    create_table :product_colorways do |t|
      t.references :product, null: false, foreign_key: true
      t.bigint :source_attachment_id, null: false
      t.string :name, null: false
      t.string :hex, null: false
      t.string :prompt
      t.jsonb :points, null: false, default: []
      t.jsonb :report, null: false, default: {}
      t.timestamps
    end

    add_index :product_colorways, [ :product_id, :source_attachment_id, :hex ],
              unique: true, name: "index_product_colorways_on_source_and_hex"
    add_index :product_colorways, :source_attachment_id
    add_foreign_key :product_colorways, :active_storage_attachments,
                    column: :source_attachment_id, on_delete: :cascade
  end
end
