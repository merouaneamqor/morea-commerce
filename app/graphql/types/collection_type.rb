# frozen_string_literal: true

module Types
  class CollectionType < BaseObject
    field :id, ID, null: false
    field :slug, String, null: false
    field :published, Boolean, null: false
    field :position, Integer, null: false
    field :translations, [ CollectionTranslationType ], null: false
    field :product_slugs, [ String ], null: false
    field :image, ImageType, null: true

    def product_slugs
      object.products.map(&:slug)
    end

    def image
      return unless object.image.attached?

      Catalog::Images.present(object.image, store: object.store, position: 0)
    end
  end
end
