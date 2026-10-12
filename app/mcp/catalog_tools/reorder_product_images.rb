# frozen_string_literal: true

module CatalogTools
  class ReorderProductImages < MCP::Tool
    description "Set product image order. The first id becomes the cover. Ids not listed follow in their previous order."
    input_schema(
      properties: {
        slug: { type: "string" },
        imageIds: { type: "array", items: { type: "string" } }
      },
      required: %w[slug imageIds]
    )

    def self.call(slug:, imageIds:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $imageIds: [ID!]!) {
            reorderProductImages(slug: $slug, imageIds: $imageIds) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, imageIds: imageIds }
      )
    end
  end
end
