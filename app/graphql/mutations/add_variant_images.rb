# frozen_string_literal: true

module Mutations
  class AddVariantImages < BaseMutation
    argument :slug, String, required: true
    argument :variant_id, ID, required: true
    argument :images, [ Types::ImageUploadInput ], required: true

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, variant_id:, images:)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      variant = product.product_variants.find_by(id: variant_id)
      return failure("Variant not found: #{variant_id}").merge(product: nil) unless variant

      Catalog::Images.attach_variant!(variant, images)
      { product: product.reload, errors: [] }
    rescue Catalog::Images::Error => error
      { product: nil, errors: [ error.message ] }
    end
  end
end
