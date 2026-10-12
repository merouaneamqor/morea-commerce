# frozen_string_literal: true

module Mutations
  class CreateCollection < BaseMutation
    argument :translations, [ Types::CollectionTranslationInput ], required: true
    argument :slug, String, required: false
    argument :published, Boolean, required: false
    argument :position, Integer, required: false
    argument :product_slugs, [ String ], required: false

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(translations:, product_slugs: nil, **attrs)
      collection = store.collections.new(
        published: attrs[:published].nil? ? true : attrs[:published],
        position: attrs[:position] || 0
      )
      collection.slug = attrs[:slug] if attrs[:slug].present?
      Catalog::Translations.assign!(collection, translations)

      ids = nil
      if product_slugs
        ids, missing = Catalog::Membership.product_ids_for(store, product_slugs)
        return failure(missing.map { |slug| "Unknown product: #{slug}" }).merge(collection: nil) if missing.any?
      end

      return payload(collection, :collection) unless collection.save

      Catalog::Membership.apply_products!(collection, ids) if product_slugs
      { collection: collection.reload, errors: [] }
    end
  end
end
