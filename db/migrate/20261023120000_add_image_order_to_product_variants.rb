class AddImageOrderToProductVariants < ActiveRecord::Migration[8.1]
  def change
    add_column :product_variants, :image_order, :jsonb, default: [], null: false
  end
end
