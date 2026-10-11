# frozen_string_literal: true

class CreateProductColorVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :product_color_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, foreign_key: true
      t.bigint :source_attachment_id, null: false
      t.string :hex_color, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.timestamps
    end

    add_index :product_color_variants, :source_attachment_id
    add_index :product_color_variants, %i[product_id source_attachment_id hex_color],
              name: "index_color_variants_on_product_source_hex"
  end
end
