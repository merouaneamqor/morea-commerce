# frozen_string_literal: true

module CatalogTools
  class UpdateProduct < MCP::Tool
    description "Update a product by slug. Omitted fields stay unchanged. newSlug renames it. clearCompareAt removes the compare-at price. Empty sku clears the SKU."
    input_schema(
      properties: {
        slug: { type: "string" },
        newSlug: { type: "string" },
        status: { type: "string", enum: %w[draft active archived] },
        priceDh: { type: "integer" },
        compareAtDh: { type: "integer" },
        clearCompareAt: { type: "boolean" },
        currency: { type: "string" },
        sku: { type: "string" },
        stock: { type: "integer" },
        trackInventory: { type: "boolean" },
        featured: { type: "boolean" },
        position: { type: "integer" },
        translations: { type: "array", items: { type: "object" } }
      },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:, **attrs)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation(
            $slug: String!, $newSlug: String, $status: String, $priceDh: Int, $compareAtDh: Int,
            $clearCompareAt: Boolean, $currency: String, $sku: String, $stock: Int,
            $trackInventory: Boolean, $featured: Boolean, $position: Int,
            $translations: [ProductTranslationInput!]
          ) {
            updateProduct(
              slug: $slug, newSlug: $newSlug, status: $status, priceDh: $priceDh, compareAtDh: $compareAtDh,
              clearCompareAt: $clearCompareAt, currency: $currency, sku: $sku, stock: $stock,
              trackInventory: $trackInventory, featured: $featured, position: $position, translations: $translations
            ) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug }.merge(attrs)
      )
    end
  end
end
