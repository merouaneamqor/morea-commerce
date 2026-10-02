# frozen_string_literal: true

class AddImageOrderToProducts < ActiveRecord::Migration[8.1]
  def change
    # Attachment ids of the product images, in display order (first = main image)
    add_column :products, :image_order, :integer, array: true, default: [], null: false
  end
end
