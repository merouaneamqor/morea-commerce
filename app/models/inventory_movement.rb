class InventoryMovement < ApplicationRecord
  belongs_to :product
  belongs_to :product_variant, optional: true
  belongs_to :order, optional: true

  validates :quantity, :reason, presence: true
end
