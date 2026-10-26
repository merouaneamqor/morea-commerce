class Store < ApplicationRecord
  include Translatable

  RESERVED_SUBDOMAINS = %w[www app admin api].freeze
  # Look of the merchant admin; "current" is the original grey interface.
  ADMIN_THEMES = %w[blue dark light current].freeze
  BILLING_INTERVALS = %w[monthly yearly].freeze
  BILLING_STATUSES = %w[trial active past_due canceled].freeze

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
  has_many :invoices, dependent: :destroy
  has_many :agent_changesets, dependent: :destroy
  has_many :store_connections, dependent: :destroy
  has_many :store_expenses, dependent: :destroy

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :tagline, :about, :cod_label, :cod_note, :campaign_title, :campaign_season, :campaign_cta, :announcement

  belongs_to :featured_product, class_name: "Product", optional: true
  belongs_to :featured_collection, class_name: "Collection", optional: true

  validates :name, :slug, presence: true
  validates :admin_theme, inclusion: { in: ADMIN_THEMES }
  validates :storefront_enabled, inclusion: { in: [ true, false ] }
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must be lowercase letters, numbers, and hyphens" }
  validates :slug, exclusion: { in: RESERVED_SUBDOMAINS }
  validates :shipping_cents, :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :free_shipping_threshold_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates :billing_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_interval, inclusion: { in: BILLING_INTERVALS }
  validates :billing_status, inclusion: { in: BILLING_STATUSES }
  validates :meta_pixel_id, format: { with: /\A\d{5,20}\z/, message: "must be 5–20 digits" }, allow_blank: true
  validates :tiktok_pixel_id, format: { with: /\A[A-Za-z0-9]{10,40}\z/, message: "must be 10–40 letters or numbers" }, allow_blank: true

  before_validation :normalize_pixel_ids
  before_validation :normalize_slug
  before_validation :assign_default_billing_period_end, on: :create
  after_save :sync_privacy_policy_page, if: :privacy_settings_changed?

  PRIVACY_SYNC_ATTRIBUTES = %i[legal_entity_name cndp_authorization privacy_rights_contact name email phone].freeze

  scope :with_sendit, -> {
    where.not(sendit_public_key: [ nil, "" ]).where.not(sendit_secret_key: [ nil, "" ])
  }

  # Product name shown on the apex landing page and sign-in (not a tenant store name).
  def self.platform_name
    ENV.fetch("PLATFORM_NAME", "Seallo crm")
  end

  def self.base_domain
    ENV.fetch("APP_BASE_DOMAIN") { Rails.env.local? ? "lvh.me" : "localhost" }
  end

  def self.platform_origin
    host = base_domain
    port = ENV["APP_PORT"].presence
    "#{Rails.env.local? ? "http" : "https"}://#{host}#{":#{port}" if port}"
  end

  # Local development also answers on *.localhost (browsers resolve it to loopback without DNS).
  def self.base_domains
    [ base_domain.downcase, ("localhost" if Rails.env.local?) ].compact.uniq
  end

  def self.apex_host?(host)
    hostname = host.to_s.downcase.split(":").first
    base_domains.any? { |domain| hostname == domain || hostname == "www.#{domain}" }
  end

  def self.find_by_host(host)
    hostname = host.to_s.downcase.split(":").first
    return if hostname.blank?

    # Direct loopback IP access opens the default store in local dev
    return find_by(slug: ENV.fetch("DEFAULT_STORE_SLUG", "morea")) if Rails.env.local? && hostname == "127.0.0.1"
    return if apex_host?(hostname)

    base_domains.each do |domain|
      suffix = ".#{domain}"
      next unless hostname.end_with?(suffix)

      slug = hostname.delete_suffix(suffix)
      next if slug.blank? || slug.include?(".") || RESERVED_SUBDOMAINS.include?(slug)

      return find_by(slug: slug)
    end
    nil
  end

  def pixels_configured?
    meta_pixel_id.present? || tiktok_pixel_id.present?
  end

  def data_controller_name
    legal_entity_name.presence || name
  end

  def privacy_rights_contact_display
    privacy_rights_contact.presence || email.presence || phone.presence || "—"
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

  def billing_amount_dh
    billing_amount_cents.to_i / 100
  end

  def billing_amount_dh=(value)
    self.billing_amount_cents = value.to_i * 100
  end

  # Older workspaces retain their existing billing policy. Self-service accounts
  # need a paid, current billing period before merchant operations are available.
  def operational_access?
    return true unless subscription_required?

    billing_status == "active" && billing_period_ends_on.present? && billing_period_ends_on >= Date.current
  end

  def billing_past_due?
    billing_status == "past_due" || invoices.overdue.exists?
  end

  def sync_billing_past_due!
    return unless invoices.overdue.exists?
    return if billing_status == "past_due"

    update!(billing_status: "past_due")
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

  def self.find_by_api_token(token)
    return if token.blank?

    find_by(api_token_digest: digest_api_token(token))
  end

  def self.digest_api_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Returns the plaintext token once. Only the digest is stored.
  def generate_api_token!
    token = "morea_#{SecureRandom.urlsafe_base64(32)}"
    update!(
      api_token_digest: self.class.digest_api_token(token),
      api_token_last_four: token.last(4)
    )
    token
  end

  def revoke_api_token!
    update!(api_token_digest: nil, api_token_last_four: nil)
  end

  private

  def privacy_settings_changed?
    PRIVACY_SYNC_ATTRIBUTES.any? { |attr| saved_change_to_attribute?(attr) }
  end

  def sync_privacy_policy_page
    DataProtection::SyncPrivacyPage.call(self)
  end

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end

  def normalize_pixel_ids
    self.meta_pixel_id = meta_pixel_id.to_s.strip.presence
    self.tiktok_pixel_id = tiktok_pixel_id.to_s.strip.presence
  end

  def assign_default_billing_period_end
    return if billing_period_ends_on.present?

    self.billing_period_ends_on =
      case billing_interval
      when "yearly" then Date.current + 1.year
      else Date.current + 1.month
      end
  end
end
