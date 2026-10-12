# frozen_string_literal: true

module CatalogTools
  class RemoveProductImages < MCP::Tool
    description "Remove product images by attachment id (the id field on each image)."
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
            removeProductImages(slug: $slug, imageIds: $imageIds) {
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
