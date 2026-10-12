# frozen_string_literal: true

module Mutations
  class UpdateCollection < BaseMutation
    argument :slug, String, required: true
    argument :new_slug, String, required: false
    argument :published, Boolean, required: false
    argument :position, Integer, required: false
    argument :translations, [ Types::CollectionTranslationInput ], required: false

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, translations: nil, **attrs)
      collection = store.collections.includes(:translations).find_by(slug: slug)
      return failure("Collection not found: #{slug}").merge(collection: nil) unless collection

      collection.slug = attrs[:new_slug] if attrs[:new_slug].present?
      collection.published = attrs[:published] unless attrs[:published].nil?
      collection.position = attrs[:position] unless attrs[:position].nil?
      Catalog::Translations.assign!(collection, translations) if translations

      collection.save
      payload(collection, :collection)
    end
  end
end
