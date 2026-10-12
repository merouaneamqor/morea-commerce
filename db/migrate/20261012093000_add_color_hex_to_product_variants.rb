# frozen_string_literal: true

class AddColorHexToProductVariants < ActiveRecord::Migration[8.1]
  HEX_BY_NAME = {
    "blush" => "#f8cdd0",
    "rose poudré" => "#d9a8ab",
    "rose poudre" => "#d9a8ab",
    "sand" => "#d6c3b0",
    "taupe" => "#9a8b7a",
    "ink" => "#1a1716",
    "noir" => "#1a1716",
    "black" => "#1a1716",
    "white" => "#faf9f7",
    "rose" => "#e8b4b8",
    "cognac" => "#8b5a3c"
  }.freeze

  def up
    add_column :product_variants, :color_hex, :string

    say_with_time "backfill color_hex from known color names" do
      ProductVariant.reset_column_information
      ProductVariant.find_each do |variant|
        name = variant.option2_value.to_s.downcase
        hex = HEX_BY_NAME[name]
        variant.update_columns(color_hex: hex) if hex
      end
    end
  end

  def down
    remove_column :product_variants, :color_hex
  end
end
