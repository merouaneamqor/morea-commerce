# frozen_string_literal: true

module CatalogTools
  class CreateProduct < MCP::Tool
    description "Create a product. priceDh is the price in whole currency units. Include a fr translation name."
    input_schema(
      properties: {
        priceDh: { type: "integer" },
        translations: {
          type: "array",
          items: {
            type: "object",
            properties: {
              locale: { type: "string", enum: %w[fr en ar] },
              name: { type: "string" },
              shortDescription: { type: "string" },
              story: { type: "string" },
              material: { type: "string" },
              fit: { type: "string" },
              movement: { type: "string" },
              dimensions: { type: "string" },
              origin: { type: "string" },
              care: { type: "string" },
              seoTitle: { type: "string" },
              seoDescription: { type: "string" }
            },
            required: %w[locale name]
          }
        },
        slug: { type: "string" },
        status: { type: "string", enum: %w[draft active archived] },
        compareAtDh: { type: "integer" },
        currency: { type: "string" },
        sku: { type: "string" },
        stock: { type: "integer" },
        trackInventory: { type: "boolean" },
        featured: { type: "boolean" },
        position: { type: "integer" },
        collectionSlugs: { type: "array", items: { type: "string" } }
      },
      required: %w[priceDh translations]
    )

    def self.call(priceDh:, translations:, server_context:, **attrs)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation(
            $priceDh: Int!, $translations: [ProductTranslationInput!]!, $slug: String, $status: String,
            $compareAtDh: Int, $currency: String, $sku: String, $stock: Int, $trackInventory: Boolean,
            $featured: Boolean, $position: Int, $collectionSlugs: [String!]
          ) {
            createProduct(
              priceDh: $priceDh, translations: $translations, slug: $slug, status: $status,
              compareAtDh: $compareAtDh, currency: $currency, sku: $sku, stock: $stock,
              trackInventory: $trackInventory, featured: $featured, position: $position,
              collectionSlugs: $collectionSlugs
            ) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { priceDh: priceDh, translations: translations }.merge(attrs)
      )
    end
  end
end
