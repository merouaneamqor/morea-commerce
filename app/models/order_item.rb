class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product
  belongs_to :product_variant, optional: true

  validates :product_name, :quantity, :unit_price_cents, :total_cents, presence: true
end
