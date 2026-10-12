# frozen_string_literal: true

module CatalogTools
  class DeleteProductVariants < MCP::Tool
    description "Delete variants by id or by size and color. Requires confirm: true. Lines already on an order keep the variant name."
    input_schema(
      properties: {
        slug: { type: "string" },
        confirm: { type: "boolean", description: "Must be true" },
        ids: { type: "array", items: { type: "string" } },
        keys: {
          type: "array",
          items: {
            type: "object",
            properties: {
              size: { type: "string" },
              color: { type: "string" }
            }
          }
        }
      },
      required: %w[slug confirm]
    )

    def self.call(slug:, confirm:, server_context:, ids: nil, keys: nil)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $confirm: Boolean!, $ids: [ID!], $keys: [VariantKeyInput!]) {
            deleteProductVariants(slug: $slug, confirm: $confirm, ids: $ids, keys: $keys) {
              product { slug variants { id size color colorHex sku stock active priceDh } }
              errors
            }
          }
        GQL
        variables: { slug: slug, confirm: confirm, ids: ids, keys: keys }.compact
      )
    end
  end
end
