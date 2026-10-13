# frozen_string_literal: true

module Catalog
  module Autonomy
    LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze
    DEFAULT_PROFILE = {
      "tone" => "Clear, refined, and practical. Match the store's existing voice.",
      "targetAudience" => "Shoppers on the storefront",
      "languages" => LOCALES,
      "pricingRules" => {
        "currency" => "DH",
        "minPriceDh" => 0,
        "requireCompareAt" => false
      },
      "namingConventions" => "Prefer short product names. Keep slugs lowercase with hyphens.",
      "brandGuidelines" => "",
      "requiredProductFields" => %w[name shortDescription],
      "requiredSeoFields" => %w[seoTitle seoDescription],
      "approvalRules" => {
        "contentEdits" => 1,
        "collectionAssignment" => 1,
        "priceChanges" => 2,
        "slugChanges" => 2,
        "structuralCollectionChanges" => 2,
        "deletes" => 3
      }
    }.freeze

    PRODUCT_TRANSLATION_FIELDS = %w[
      name shortDescription story material fit movement dimensions origin care seoTitle seoDescription
    ].freeze

    COLLECTION_TRANSLATION_FIELDS = %w[name subtitle description].freeze

    module_function

    def profile_for(store)
      stored = store.agent_profile.is_a?(Hash) ? store.agent_profile.deep_stringify_keys : {}
      DEFAULT_PROFILE.deep_merge(stored).merge(
        "storeName" => store.name,
        "storeSlug" => store.slug,
        "origin" => store.origin,
        "currency" => store.currency,
        "lowStockThreshold" => store.low_stock_threshold,
        "availableLocales" => LOCALES,
        "defaultLocale" => Morea::Locales::DEFAULT.to_s
      )
    end

    def merge_profile!(store, attrs)
      incoming = attrs.deep_stringify_keys
      current = store.agent_profile.is_a?(Hash) ? store.agent_profile.deep_stringify_keys : {}
      store.agent_profile = current.deep_merge(incoming)
      store.save!
      profile_for(store)
    end

    def product_schema
      {
        "entity" => "product",
        "statuses" => Product::STATUSES,
        "locales" => LOCALES,
        "defaultLocale" => Morea::Locales::DEFAULT.to_s,
        "fields" => [
          field("slug", "string", required: true, notes: "Unique per store. Use newSlug to rename."),
          field("status", "string", required: true, enum: Product::STATUSES),
          field("priceDh", "integer", required: true, notes: "Whole currency units, not cents."),
          field("compareAtDh", "integer", required: false),
          field("currency", "string", required: false, default: "DH"),
          field("sku", "string", required: false, notes: "Empty string clears the SKU."),
          field("stock", "integer", required: false, notes: "Product-level only when there are no variants. Prefer adjust_stock/set_stock so the ledger records the change."),
          field("trackInventory", "boolean", required: false),
          field("featured", "boolean", required: false),
          field("position", "integer", required: false),
          field("collectionSlugs", "string[]", required: false, notes: "Full membership replace via set_product_collections."),
          field("translations", "object[]", required: true, notes: "Create needs fr name. Fields: #{PRODUCT_TRANSLATION_FIELDS.join(', ')}."),
          field("variants", "object[]", required: false, notes: "size + color pairs via set_product_variants. Variant stock writes ledger movements."),
          field("images", "object[]", required: false, notes: "Gallery; position 0 is the cover.")
        ],
        "inventoryTools" => %w[list_inventory list_low_stock inventory_summary list_inventory_movements adjust_stock set_stock],
        "inventoryReasons" => InventoryMovement::MANUAL_REASONS,
        "translationFields" => PRODUCT_TRANSLATION_FIELDS,
        "approvalLevels" => {
          "1" => "Automatic content, translation, SEO, and assignment to existing collections",
          "2" => "Preview first: prices, slugs, create product, structural collection changes, variants, stock adjusts",
          "3" => "Restricted: permanent deletes and other high-impact actions"
        }
      }
    end

    def field(name, type, required:, enum: nil, default: nil, notes: nil)
      {
        "name" => name,
        "type" => type,
        "required" => required,
        "enum" => enum,
        "default" => default,
        "notes" => notes
      }.compact
    end
  end
end
