# frozen_string_literal: true

module CatalogTools
  class SetProductVariants < MCP::Tool
    description "Create or update size and color variants on a product. A size+color that already exists is updated. Omit a variant to leave it unchanged. priceDh blank uses the product price. When variants exist, sellable stock is the sum of active variant stock."
    input_schema(
      properties: {
        slug: { type: "string" },
        variants: {
          type: "array",
          items: {
            type: "object",
            properties: {
              size: { type: "string" },
              color: { type: "string" },
              colorHex: { type: "string" },
              sku: { type: "string" },
              stock: { type: "integer" },
              active: { type: "boolean" },
              priceDh: { type: "integer", description: "Blank uses the product price" }
            }
          }
        }
      },
      required: %w[slug variants]
    )

    def self.call(slug:, variants:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $variants: [VariantInput!]!) {
            setProductVariants(slug: $slug, variants: $variants) {
              product { slug variants { id size color colorHex sku stock active priceDh } }
              errors
            }
          }
        GQL
        variables: { slug: slug, variants: variants }
      )
    end
  end
end
