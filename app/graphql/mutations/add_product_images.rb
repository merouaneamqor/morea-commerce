# frozen_string_literal: true

module Mutations
  class AddProductImages < BaseMutation
    argument :slug, String, required: true
    argument :images, [ Types::ImageUploadInput ], required: true

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, images:)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      Catalog::Images.attach_product!(product, images)
      { product: product.reload, errors: [] }
    rescue Catalog::Images::Error => error
      { product: nil, errors: [ error.message ] }
    end
  end
end
