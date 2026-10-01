class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product
  belongs_to :product_variant, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }

  def line_total_cents
    unit_price_cents * quantity
  end

  def display_name
    [product.name, product_variant&.display_name].compact.join(" — ")
  end
end
