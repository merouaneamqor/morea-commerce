# frozen_string_literal: true

# Shared home / landing page section behavior (kinds, copy, settings, images).
module SectionBlock
  extend ActiveSupport::Concern

  KINDS = {
    "hero" => "Image banner",
    "ticker" => "Scrolling text",
    "featured_collection" => "Featured collection",
    "collection_list" => "Collection list",
    "image_with_text" => "Image with text",
    "rich_text" => "Rich text"
  }.freeze

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

  included do
    include Translatable
    include StoreLinkable
    include Positioned

    has_one_attached :image

    translates :heading, :subheading, :body, :button_label
    store_accessor :settings, :image_url, :link, :collection_id, :limit, :image_position

    validates :kind, inclusion: { in: KINDS.keys }

    scope :ordered, -> { order(:position, :id) }
    scope :visible, -> { where(visible: true) }
  end

  def image_src
    image.attached? ? MediaUrl.for(image, store: store) : image_url.presence
  end

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
end
