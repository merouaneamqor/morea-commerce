class StoreExpense < ApplicationRecord
  CATEGORIES = %w[packaging staff rent software tools other].freeze

  belongs_to :store

  validates :spent_on, :category, :amount_cents, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :note, length: { maximum: 255 }

  scope :recent, -> { order(spent_on: :desc, id: :desc) }
  scope :between, ->(range) { where(spent_on: range) }
end
