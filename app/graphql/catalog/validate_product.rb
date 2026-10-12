# frozen_string_literal: true

module Catalog
  module ValidateProduct
    module_function

    def call(store, slug:)
      product = store.products.includes(:translations, :collections, :product_variants).find_by(slug: slug)
      return { ok: false, errors: [ "Product not found: #{slug}" ], issues: [], schema: Autonomy.product_schema } unless product

      profile = Autonomy.profile_for(store)
      audit = Audit.store(store, status: product.status)
      issues = audit[:issues].select { |issue| issue[:entity_type] == "product" && issue[:entity_slug] == product.slug }

      errors = []
      errors << "French name is required" if product.translation_for("fr")&.name.blank?
      errors << "Price must be >= 0" if product.price_dh.to_i.negative?
      if product.compare_at_dh.present? && product.compare_at_dh.to_i <= product.price_dh.to_i
        errors << "compareAtDh must be greater than priceDh"
      end
      errors << "Unknown status" unless Product::STATUSES.include?(product.status)

      Array(profile["languages"]).each do |locale|
        next if product.locale_complete?(locale)

        errors << "Missing required translation for locale #{locale}"
      end

      {
        ok: errors.empty? && issues.none? { |issue| issue[:severity] == "high" },
        slug: product.slug,
        errors: errors,
        issues: issues,
        schema: Autonomy.product_schema
      }
    end
  end
end
