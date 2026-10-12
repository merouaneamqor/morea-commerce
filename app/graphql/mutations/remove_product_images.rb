# frozen_string_literal: true

module Mutations
  class RemoveProductImages < BaseMutation
    argument :slug, String, required: true
    argument :image_ids, [ ID ], required: true

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, image_ids:)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      Catalog::Images.remove_product!(product, image_ids)
      { product: product.reload, errors: [] }
    rescue Catalog::Images::Error => error
      { product: nil, errors: [ error.message ] }
    end
  end
end
