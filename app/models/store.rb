class Store < ApplicationRecord
  include Translatable

  has_many :products, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :carts, dependent: :destroy
  has_many :discounts, dependent: :destroy
  has_many :translations, class_name: "StoreTranslation", dependent: :destroy, inverse_of: :store
  has_many :home_sections, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :menu_items, dependent: :destroy

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :tagline, :about, :cod_label, :cod_note, :campaign_title, :campaign_season, :campaign_cta, :announcement

  belongs_to :featured_product, class_name: "Product", optional: true
  belongs_to :featured_collection, class_name: "Collection", optional: true

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  def self.current
    order(:id).first
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
end
