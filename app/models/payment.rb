# frozen_string_literal: true

# A subscription payment declared by a merchant; seallo verifies the bank transfer before activating the plan.
class Payment < ApplicationRecord
  STATUSES = %w[pending paid rejected].freeze
  METHODS = %w[transfer card].freeze

  belongs_to :store

  validates :plan, inclusion: { in: ->(_) { Plans.list.keys } }
  validates :billing, inclusion: { in: Plans::BILLINGS }
  validates :payment_method, inclusion: { in: METHODS }
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reference, length: { maximum: 100 }

  scope :pending, -> { where(status: "pending") }
end
