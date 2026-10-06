class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :cart_items, dependent: :nullify
  has_many :order_items, dependent: :nullify
  has_many :inventory_movements, dependent: :nullify

  validates :name, presence: true
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def price_dh
    price_cents.to_i / 100 if price_cents.present?
  end

  def price_dh=(value)
    self.price_cents = value.present? ? value.to_i * 100 : nil
  end

  def unit_price_cents
    price_cents.presence || product.price_cents
  end

  def display_name
    name.presence || [option1_value, option2_value].compact.join(" / ")
  end
end
