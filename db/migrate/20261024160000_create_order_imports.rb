# frozen_string_literal: true

class CreateOrderImports < ActiveRecord::Migration[8.1]
  def change
    create_table :order_imports do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :order, null: false, foreign_key: { on_delete: :cascade }
      t.string :source, null: false, limit: 64
      t.string :external_id, null: false, limit: 255
      t.timestamps
    end

    add_index :order_imports, [ :store_id, :source, :external_id ], unique: true,
      name: "index_order_imports_on_tenant_source_external_id"
  end
end
