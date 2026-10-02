# frozen_string_literal: true

# A block of the home page, ordered and editable from Online Store › Customize
class HomeSection < ApplicationRecord
  include Translatable
  include StoreLinkable
  include Positioned

  KINDS = {
    "hero" => "Image banner",
    "ticker" => "Scrolling text",
    "featured_collection" => "Featured collection",
    "collection_list" => "Collection list",
    "image_with_text" => "Image with text",
    "rich_text" => "Rich text"
  }.freeze

  # Which translated fields each kind uses (shown in the admin editor)
  TEXT_FIELDS = {
    "hero" => %i[subheading heading button_label],
    "ticker" => %i[body],
    "featured_collection" => %i[subheading heading],
    "collection_list" => %i[subheading heading],
    "image_with_text" => %i[subheading heading body button_label],
    "rich_text" => %i[subheading body button_label]
  }.freeze

  SETTING_FIELDS = {
    "hero" => %i[image_url link],
    "ticker" => [],
    "featured_collection" => %i[collection_id limit],
    "collection_list" => %i[limit],
    "image_with_text" => %i[image_url link image_position],
    "rich_text" => %i[image_url link]
  }.freeze

  belongs_to :store
  has_many :translations, class_name: "HomeSectionTranslation", dependent: :destroy, inverse_of: :home_section

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :heading, :subheading, :body, :button_label
  store_accessor :settings, :image_url, :link, :collection_id, :limit, :image_position

  validates :kind, inclusion: { in: KINDS.keys }

  scope :ordered, -> { order(:position, :id) }
  scope :visible, -> { where(visible: true) }

  def label
    KINDS.fetch(kind, kind.humanize)
  end

  def text_fields
    TEXT_FIELDS.fetch(kind, [])
  end

  def setting_fields
    SETTING_FIELDS.fetch(kind, [])
  end

  def preview_text
    heading.presence || subheading.presence || body.to_s.lines.first.to_s.strip.presence
  end

  def locale_complete?(locale)
    t = translation_for(locale)
    t.present? && text_fields.any? { |f| t.public_send(f).to_s.strip.present? }
  end

  def collection
    @collection ||= store.collections.published.find_by(id: collection_id) ||
      store.featured_collection || store.collections.published.order(:position).first
  end

  def item_limit(default = 4)
    limit.to_i.positive? ? limit.to_i.clamp(1, 12) : default
  end

  def products
    return Product.none unless collection

    collection.products.active.includes(:translations, images_attachments: :blob).limit(item_limit)
  end

  def ticker_items
    body.to_s.lines.map(&:strip).compact_blank
  end

  def image_on_right?
    image_position == "right"
  end

  private

  def position_scope
    store.home_sections
  end
end
