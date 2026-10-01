class Cart < ApplicationRecord
  belongs_to :store
  has_many :cart_items, dependent: :destroy

  validates :token, presence: true, uniqueness: true

  before_validation :ensure_token, on: :create

  def subtotal_cents
    cart_items.sum { |item| item.unit_price_cents * item.quantity }
  end

  def item_count
    cart_items.sum(:quantity)
  end

  def empty?
    cart_items.empty?
  end

  def add_product!(product, quantity: 1, variant: nil)
    quantity = quantity.to_i.clamp(1, 99)
    item = cart_items.find_or_initialize_by(product: product, product_variant: variant)
    item.quantity = item.new_record? ? quantity : item.quantity + quantity
    item.unit_price_cents = variant&.unit_price_cents || product.price_cents
    item.save!
    item
  end

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end
