class Store < ApplicationRecord
  include Translatable

  RESERVED_SUBDOMAINS = %w[www app admin api].freeze

  has_many :products, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :carts, dependent: :destroy
  has_many :discounts, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :translations, class_name: "StoreTranslation", dependent: :destroy, inverse_of: :store
  has_many :home_sections, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :menu_items, dependent: :destroy

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :tagline, :about, :cod_label, :cod_note, :campaign_title, :campaign_season, :campaign_cta, :announcement

  belongs_to :featured_product, class_name: "Product", optional: true
  belongs_to :featured_collection, class_name: "Collection", optional: true

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must be lowercase letters, numbers, and hyphens" }
  validates :slug, exclusion: { in: RESERVED_SUBDOMAINS }
  validates :shipping_cents, :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :free_shipping_threshold_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates :meta_pixel_id, format: { with: /\A\d{5,20}\z/, message: "must be 5–20 digits" }, allow_blank: true
  validates :tiktok_pixel_id, format: { with: /\A[A-Za-z0-9]{10,40}\z/, message: "must be 10–40 letters or numbers" }, allow_blank: true

  before_validation :normalize_pixel_ids
  before_validation :normalize_slug

  scope :with_sendit, -> {
    where.not(sendit_public_key: [ nil, "" ]).where.not(sendit_secret_key: [ nil, "" ])
  }

  def self.base_domain
    ENV.fetch("APP_BASE_DOMAIN") { Rails.env.local? ? "lvh.me" : "localhost" }
  end

  def self.find_by_host(host)
    hostname = host.to_s.downcase.split(":").first
    domain = base_domain.downcase
    return if hostname.blank? || hostname == domain

    suffix = ".#{domain}"
    return unless hostname.end_with?(suffix)

    slug = hostname.delete_suffix(suffix)
    return if slug.blank? || slug.include?(".") || RESERVED_SUBDOMAINS.include?(slug)

    find_by(slug: slug)
  end

  def pixels_configured?
    meta_pixel_id.present? || tiktok_pixel_id.present?
  end

  # Meta and TikTok expect ISO currency codes; storefront display uses DH.
  def pixel_currency
    case currency.to_s.upcase
    when "DH", "MAD" then "MAD"
    else currency.to_s.upcase.presence || "MAD"
    end
  end

  def sendit_configured?
    sendit_public_key.present? && sendit_secret_key.present?
  end

  def origin
    protocol = Rails.env.local? ? "http" : "https"
    host = "#{slug}.#{self.class.base_domain}"
    port = ENV["APP_PORT"].presence
    host = "#{host}:#{port}" if port.present?
    "#{protocol}://#{host}"
  end

  def shipping_dh
    shipping_cents.to_i / 100
  end

  def shipping_dh=(value)
    self.shipping_cents = value.to_i * 100
  end

  def free_shipping_threshold_dh
    free_shipping_threshold_cents.to_i / 100 if free_shipping_threshold_cents.present?
  end

  def free_shipping_threshold_dh=(value)
    self.free_shipping_threshold_cents = value.present? ? value.to_i * 100 : nil
  end

  # Flat fee, or free once the cart subtotal reaches the optional threshold.
  # Prefer Sendit city rates at checkout — this is the offline fallback.
  def shipping_cents_for(subtotal_cents)
    return 0 if free_shipping?(subtotal_cents)

    shipping_cents.to_i
  end

  def free_shipping?(subtotal_cents)
    threshold = free_shipping_threshold_cents
    threshold.present? && subtotal_cents.to_i >= threshold
  end


  # wa.me link to the store's WhatsApp ("06 12 34 56 78" -> https://wa.me/212612345678)
  def whatsapp_url(text = nil)
    phone = Phonelib.parse(whatsapp)
    return unless phone.valid?

    url = "https://wa.me/#{phone.e164.delete("+")}"
    text.present? ? "#{url}?text=#{ERB::Util.url_encode(text)}" : url
  end

  def campaign_image
    campaign_image_url.presence
  end

  def campaign_heading
    campaign_title.presence || I18n.t("store.default_campaign_title")
  end

  def campaign_subheading
    campaign_season.presence || "SS / 26"
  end

  def campaign_button
    campaign_cta.presence || I18n.t("store.default_campaign_cta")
  end

  # Saved home sections, or the built-in defaults (unsaved) until the theme is installed
  def home_sections_for_display
    sections = home_sections.visible.ordered.includes(:translations).to_a
    return sections if home_sections.exists?

    OnlineStoreDefaults.new(self).home_sections
  end

  def install_online_store_defaults!
    OnlineStoreDefaults.new(self).install!
  end

  private

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end

  def normalize_pixel_ids
    self.meta_pixel_id = meta_pixel_id.to_s.strip.presence
    self.tiktok_pixel_id = tiktok_pixel_id.to_s.strip.presence
  end
end
