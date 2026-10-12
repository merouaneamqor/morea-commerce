# frozen_string_literal: true

module Mutations
  class SetCollectionImage < BaseMutation
    argument :slug, String, required: true
    argument :image, Types::ImageUploadInput, required: true

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, image:)
      collection = store.collections.find_by(slug: slug)
      return failure("Collection not found: #{slug}").merge(collection: nil) unless collection

      Catalog::Images.attach_collection!(collection, image)
      { collection: collection.reload, errors: [] }
    rescue Catalog::Images::Error => error
      { collection: nil, errors: [ error.message ] }
    end
  end
end
