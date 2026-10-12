# frozen_string_literal: true

module Types
  class CollectionType < BaseObject
    field :id, ID, null: false
    field :slug, String, null: false
    field :published, Boolean, null: false
    field :position, Integer, null: false
    field :translations, [ CollectionTranslationType ], null: false
    field :product_slugs, [ String ], null: false
    field :cover_url, String, null: true, description: "Photo shown on collection tiles. The uploaded cover, or the first product photo when there is no cover."
    field :image, ImageType, null: true

    def product_slugs
      object.products.map(&:slug)
    end

    def cover_url
      if object.image.attached?
        Catalog::Images.absolute_url(object.image, object.store)
      else
        product = object.products.merge(Product.active).first
        attachment = product&.ordered_images&.first
        Catalog::Images.absolute_url(attachment, object.store) if attachment
      end
    end

    def image
      return unless object.image.attached?

      Catalog::Images.present(object.image, store: object.store, position: 0)
    end
  end
end
