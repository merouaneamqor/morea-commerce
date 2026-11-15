class AddSaleEndsAtToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :sale_ends_at, :datetime
  end
end
