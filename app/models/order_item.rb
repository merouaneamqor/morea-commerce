class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true

  validates :product_name, :quantity, :unit_price_cents, :total_cents, presence: true
  validate :product_belongs_to_order_store

  private

  def product_belongs_to_order_store
    errors.add(:product, "must belong to the order workspace") if product && product.store_id != order&.store_id
    if product_variant && (product.nil? || product_variant.product_id != product.id)
      errors.add(:product_variant, "must belong to the line product")
    end
  end
end
