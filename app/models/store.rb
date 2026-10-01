class Store < ApplicationRecord
  include Translatable

  has_many :products, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :carts, dependent: :destroy
  has_many :discounts, dependent: :destroy
  has_many :translations, class_name: "StoreTranslation", dependent: :destroy, inverse_of: :store

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :tagline, :about, :cod_label, :cod_note, :campaign_title, :campaign_season, :campaign_cta

  belongs_to :featured_product, class_name: "Product", optional: true
  belongs_to :featured_collection, class_name: "Collection", optional: true

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  def self.current
    order(:id).first
  end

  def campaign_image
    campaign_image_url.presence || featured_product&.image_url || featured_product&.detail_image_url
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
end
