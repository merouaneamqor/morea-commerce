class Product < ApplicationRecord
  include Translatable

  belongs_to :store
  has_many :product_variants, dependent: :destroy
  has_many :collection_products, dependent: :destroy
  has_many :collections, through: :collection_products
  has_many :cart_items, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_exception
  has_many :inventory_movements, dependent: :destroy
  has_many :translations, class_name: "ProductTranslation", dependent: :destroy, inverse_of: :product
  has_many_attached :images

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :name, :short_description, :story, :material, :fit, :movement,
             :dimensions, :origin, :care, :seo_title, :seo_description

  STATUSES = %w[draft active archived].freeze

  validates :name, :slug, :price_cents, :status, presence: true
  validates :slug, uniqueness: { scope: :store_id }
  validates :status, inclusion: { in: STATUSES }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  before_validation :ensure_slug, on: :create

  scope :active, -> { where(status: "active") }
  scope :featured, -> { where(featured: true) }
  scope :low_stock, lambda { |threshold = 5|
    where(track_inventory: true)
      .left_outer_joins(:product_variants)
      .where(
        "(product_variants.id IS NULL AND products.stock <= :threshold) OR (product_variants.active = TRUE AND product_variants.stock <= :threshold)",
        threshold: threshold
      )
      .distinct
  }

  def to_param
    slug
  end

  def price_display
    format_money(price_cents)
  end

  def price_dh
    price_cents.to_i / 100
  end

  def price_dh=(value)
    self.price_cents = value.to_i * 100
  end

  def compare_at_dh
    compare_at_cents.to_i / 100 if compare_at_cents.present?
  end

  def compare_at_dh=(value)
    self.compare_at_cents = value.present? ? value.to_i * 100 : nil
  end

  def compare_at_display
    return if compare_at_cents.blank?

    format_money(compare_at_cents)
  end

  def available?
    status == "active" && available_stock.positive?
  end

  def available_stock
    return Float::INFINITY unless track_inventory
    return stock if product_variants.empty?

    product_variants.active.sum(:stock)
  end

  # Size checklist presets live on ProductVariant::SIZE_OPTIONS (option1).
  def variant_sizes
    product_variants.filter_map(&:size_value).uniq
  end
  alias_method :variant_size_values, :variant_sizes

  def variant_color_names
    product_variants.filter_map(&:color_value).uniq
  end
  alias_method :variant_color_values, :variant_color_names

  # Unique colors with stored hex — for the admin color editor (empty when none yet).
  def variant_colors
    variant_color_names.map do |name|
      sample = product_variants.find { |v| v.color_value == name }
      { name: name, hex: sample&.color_hex.presence }
    end
  end

  def scarcity_label
    return unless track_inventory

    qty = available_stock
    return I18n.t("product.sold_out") if qty <= 0
    threshold = store&.low_stock_threshold || 5
    return I18n.t("product.only_left", count: qty) if qty <= threshold

    nil
  end

  # Images in the order set in admin; ones not yet ordered follow by upload order
  def ordered_images
    images.sort_by { |image| [ image_order.index(image.id) || image_order.size, image.id ] }
  end

  def primary_image_url
    MediaUrl.for(ordered_images.first, store: store) if images.attached?
  end

  def format_money(cents)
    "#{(cents / 100.0).to_i.to_fs(:delimited)} #{currency}"
  end

  private

  def ensure_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end
end
