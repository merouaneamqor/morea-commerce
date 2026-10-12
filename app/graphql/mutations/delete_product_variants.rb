# frozen_string_literal: true

module Mutations
  class DeleteProductVariants < BaseMutation
    argument :slug, String, required: true
    argument :confirm, Boolean, required: true
    argument :ids, [ ID ], required: false
    argument :keys, [ Types::VariantKeyInput ], required: false

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, confirm:, ids: nil, keys: nil)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      Catalog::Variants.delete!(product, ids: ids, keys: keys, confirm: confirm)
      { product: product, errors: [] }
    rescue Catalog::Variants::Error => e
      failure(e.message).merge(product: nil)
    end
  end
end
