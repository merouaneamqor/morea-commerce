# frozen_string_literal: true

module Mutations
  class SetProductCollections < BaseMutation
    argument :slug, String, required: true
    argument :collection_slugs, [ String ], required: true

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, collection_slugs:)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      ids, missing = Catalog::Membership.collection_ids_for(store, collection_slugs)
      return failure(missing.map { |item| "Unknown collection: #{item}" }).merge(product: nil) if missing.any?

      Catalog::Membership.apply_collections!(product, ids)
      { product: product.reload, errors: [] }
    end
  end
end
