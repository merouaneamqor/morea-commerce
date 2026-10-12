# frozen_string_literal: true

module Mutations
  class CreateProduct < BaseMutation
    argument :price_dh, Integer, required: true
    argument :translations, [ Types::ProductTranslationInput ], required: true
    argument :slug, String, required: false
    argument :status, String, required: false
    argument :compare_at_dh, Integer, required: false
    argument :currency, String, required: false
    argument :sku, String, required: false
    argument :stock, Integer, required: false
    argument :track_inventory, Boolean, required: false
    argument :featured, Boolean, required: false
    argument :position, Integer, required: false
    argument :collection_slugs, [ String ], required: false

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(price_dh:, translations:, collection_slugs: nil, **attrs)
      product = store.products.new(
        status: attrs[:status].presence || "draft",
        currency: attrs[:currency].presence || store.currency,
        stock: attrs[:stock] || 0,
        track_inventory: attrs[:track_inventory].nil? ? true : attrs[:track_inventory],
        featured: attrs[:featured] || false,
        position: attrs[:position] || 0,
        sku: attrs[:sku].presence
      )
      product.price_dh = price_dh
      product.compare_at_dh = attrs[:compare_at_dh] if attrs[:compare_at_dh]
      product.slug = attrs[:slug] if attrs[:slug].present?
      Catalog::Translations.assign!(product, translations)

      ids = nil
      if collection_slugs
        ids, missing = Catalog::Membership.collection_ids_for(store, collection_slugs)
        return failure(missing.map { |slug| "Unknown collection: #{slug}" }).merge(product: nil) if missing.any?
      end

      return payload(product, :product) unless product.save

      Catalog::Membership.apply_collections!(product, ids) if collection_slugs
      { product: product.reload, errors: [] }
    end
  end
end
