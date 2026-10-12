class Cart < ApplicationRecord
  # Carts newer than this are active; older carts with items are abandoned.
  RECENT_HOURS = 1

  belongs_to :store
  has_many :cart_items, dependent: :destroy

  scope :with_items, -> { where(id: CartItem.select(:cart_id)) }

  validates :token, presence: true, uniqueness: { scope: :store_id }

  before_validation :ensure_token, on: :create

  def self.recent(hours: RECENT_HOURS)
    with_items.where(updated_at: hours.hours.ago..).order(updated_at: :desc)
  end

  def self.stale(hours: RECENT_HOURS)
    cutoff = hours.zero? ? Time.current + 1.second : hours.hours.ago
    with_items.where(updated_at: ...cutoff).order(updated_at: :desc)
  end

  def subtotal_cents
    cart_items.sum { |item| item.unit_price_cents * item.quantity }
  end

  def item_count
    if cart_items.loaded?
      cart_items.sum(&:quantity)
    else
      cart_items.sum(:quantity)
    end
  end

  def empty?
    cart_items.empty?
  end

  def active?
    !empty? && updated_at >= RECENT_HOURS.hours.ago
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
