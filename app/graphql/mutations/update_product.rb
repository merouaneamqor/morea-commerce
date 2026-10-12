# frozen_string_literal: true

module Mutations
  class UpdateProduct < BaseMutation
    argument :slug, String, required: true
    argument :new_slug, String, required: false
    argument :status, String, required: false
    argument :price_dh, Integer, required: false
    argument :compare_at_dh, Integer, required: false
    argument :clear_compare_at, Boolean, required: false
    argument :currency, String, required: false
    argument :sku, String, required: false
    argument :stock, Integer, required: false
    argument :track_inventory, Boolean, required: false
    argument :featured, Boolean, required: false
    argument :position, Integer, required: false
    argument :translations, [ Types::ProductTranslationInput ], required: false

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, translations: nil, **attrs)
      product = store.products.includes(:translations).find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      product.slug = attrs[:new_slug] if attrs[:new_slug].present?
      product.status = attrs[:status] if attrs[:status].present?
      product.price_dh = attrs[:price_dh] unless attrs[:price_dh].nil?
      product.compare_at_dh = nil if attrs[:clear_compare_at]
      product.compare_at_dh = attrs[:compare_at_dh] unless attrs[:compare_at_dh].nil?
      product.currency = attrs[:currency] if attrs[:currency].present?
      product.sku = attrs[:sku].presence if attrs.key?(:sku) && !attrs[:sku].nil?
      product.stock = attrs[:stock] unless attrs[:stock].nil?
      product.track_inventory = attrs[:track_inventory] unless attrs[:track_inventory].nil?
      product.featured = attrs[:featured] unless attrs[:featured].nil?
      product.position = attrs[:position] unless attrs[:position].nil?
      Catalog::Translations.assign!(product, translations) if translations

      product.save
      payload(product, :product)
    end
  end
end
