# frozen_string_literal: true

module Mutations
  class RemoveCollectionImage < BaseMutation
    argument :slug, String, required: true

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:)
      collection = store.collections.find_by(slug: slug)
      return failure("Collection not found: #{slug}").merge(collection: nil) unless collection

      Catalog::Images.remove_collection!(collection)
      { collection: collection.reload, errors: [] }
    rescue Catalog::Images::Error => error
      { collection: nil, errors: [ error.message ] }
    end
  end
end
