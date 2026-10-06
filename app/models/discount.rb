class Discount < ApplicationRecord
  belongs_to :store

  TYPES = %w[percent fixed].freeze

  validates :code, :discount_type, :value, presence: true
  validates :code, uniqueness: { scope: :store_id }
  validates :discount_type, inclusion: { in: TYPES }
  validates :value, numericality: { greater_than: 0 }
  validates :value, numericality: { less_than_or_equal_to: 100 }, if: -> { discount_type == "percent" }

  before_validation :normalize_code

  scope :active, -> { where(active: true) }
  scope :current, -> {
    now = Time.current
    active.where("starts_at IS NULL OR starts_at <= ?", now)
          .where("ends_at IS NULL OR ends_at >= ?", now)
  }

  def self.find_usable(code)
    current.find_by(code: code.to_s.strip.upcase)
  end

  def usable?
    return false unless active?
    return false if starts_at.present? && starts_at > Time.current
    return false if ends_at.present? && ends_at < Time.current

    true
  end

  def amount_for(subtotal_cents)
    subtotal = subtotal_cents.to_i
    return 0 if subtotal <= 0

    amount = if discount_type == "percent"
      (subtotal * value / 100.0).round
    else
      value * 100
    end

    [ amount, subtotal ].min
  end

  def label
    discount_type == "percent" ? "#{value}%" : "#{value} #{store.currency}"
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase.presence
  end
end
