# frozen_string_literal: true

module Mutations
  class SetCollectionProducts < BaseMutation
    argument :slug, String, required: true
    argument :product_slugs, [ String ], required: true

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, product_slugs:)
      collection = store.collections.find_by(slug: slug)
      return failure("Collection not found: #{slug}").merge(collection: nil) unless collection

      ids, missing = Catalog::Membership.product_ids_for(store, product_slugs)
      return failure(missing.map { |item| "Unknown product: #{item}" }).merge(collection: nil) if missing.any?

      Catalog::Membership.apply_products!(collection, ids)
      { collection: collection.reload, errors: [] }
    end
  end
end
