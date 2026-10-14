class InventoryMovement < ApplicationRecord
  MANUAL_REASONS = %w[manual_adjustment received damaged correction].freeze
  ORDER_REASONS = %w[order_confirmed order_cancelled order_returned order_edited].freeze
  REASONS = (MANUAL_REASONS + ORDER_REASONS).freeze

  belongs_to :product
  belongs_to :product_variant, optional: true
  belongs_to :order, optional: true

  validates :quantity, :reason, presence: true
  validates :reason, inclusion: { in: REASONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_reason, ->(reason) { where(reason: reason) }
end
