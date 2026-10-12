# frozen_string_literal: true

module Types
  class ProductType < BaseObject
    field :id, ID, null: false
    field :slug, String, null: false
    field :status, String, null: false
    field :price_dh, Integer, null: false
    field :compare_at_dh, Integer, null: true
    field :currency, String, null: false
    field :sku, String, null: true
    field :stock, Integer, null: false
    field :track_inventory, Boolean, null: false
    field :featured, Boolean, null: false
    field :position, Integer, null: false
    field :translations, [ ProductTranslationType ], null: false
    field :collection_slugs, [ String ], null: false
    field :cover_url, String, null: true, description: "Photo shown on the store. Same file as the first image."
    field :images, [ ImageType ], null: false

    def collection_slugs
      object.collections.map(&:slug)
    end

    def cover_url
      attachment = object.ordered_images.first
      Catalog::Images.absolute_url(attachment, object.store) if attachment
    end

    def images
      object.ordered_images.each_with_index.map do |attachment, index|
        Catalog::Images.present(attachment, store: object.store, position: index)
      end
    end
  end
end
