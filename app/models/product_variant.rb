class ProductVariant < ApplicationRecord
  # option1 = Size, option2 = Color
  SIZE_OPTION_NAME = "Size"
  COLOR_OPTION_NAME = "Color"
  SIZE_OPTIONS = %w[XS S M L XL XXL].freeze
  PLACEHOLDER_HEX = "#c4b8b0"

  belongs_to :product
  has_many_attached :images
  has_many :cart_items, dependent: :nullify
  has_many :order_items, dependent: :nullify
  has_many :inventory_movements, dependent: :nullify

  before_validation :derive_name_from_options
  before_validation :normalize_color_hex

  validates :name, presence: true
  validates :stock, numericality: { greater_than_or_equal_to: 0 }
  validates :color_hex, format: { with: /\A#[0-9a-fA-F]{6}\z/, allow_blank: true }

  scope :active, -> { where(active: true) }

  def self.normalize_hex(value)
    hex = value.to_s.strip
    hex = "##{hex}" if hex.match?(/\A[0-9a-fA-F]{6}\z/)
    hex.match?(/\A#[0-9a-fA-F]{6}\z/) ? hex.downcase : nil
  end

  # Stable rank for XS–XXL; unknown / custom sizes sort after presets.
  def self.size_rank(value)
    idx = SIZE_OPTIONS.index(value.to_s.upcase)
    idx.nil? ? 99 : idx
  end

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
    name.presence || [ option1_value, option2_value ].compact_blank.join(" / ")
  end

  def option_key
    [ option1_value.to_s.strip, option2_value.to_s.strip ]
  end

  def size_value
    option1_value.presence
  end

  def color_value
    option2_value.presence
  end

  def swatch_hex
    color_hex.presence || PLACEHOLDER_HEX
  end

  def ordered_images
    images.sort_by { |image| [ image_order.index(image.id) || image_order.size, image.id ] }
  end

  private

  def derive_name_from_options
    derived = [ option1_value, option2_value ].map { |v| v.to_s.strip }.compact_blank.join(" / ")
    self.name = derived if derived.present?
  end

  def normalize_color_hex
    if option2_value.blank?
      self.color_hex = nil
      return
    end

    self.color_hex = self.class.normalize_hex(color_hex)
  end
end
