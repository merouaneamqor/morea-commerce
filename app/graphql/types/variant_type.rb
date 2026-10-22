# frozen_string_literal: true

module Types
  class VariantType < BaseObject
    field :id, ID, null: false
    field :size, String, null: true
    field :color, String, null: true
    field :color_hex, String, null: true
    field :sku, String, null: true
    field :stock, Integer, null: false
    field :active, Boolean, null: false
    field :price_dh, Integer, null: true
    field :images, [ ImageType ], null: false

    def size
      object.size_value
    end

    def color
      object.color_value
    end

    def images
      object.ordered_images.each_with_index.map do |attachment, index|
        Catalog::Images.present(attachment, store: object.product.store, position: index)
      end
    end
  end
end
