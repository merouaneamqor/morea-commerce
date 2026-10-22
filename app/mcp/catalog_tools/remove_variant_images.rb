# frozen_string_literal: true

module CatalogTools
  class RemoveVariantImages < MCP::Tool
    description "Remove images from a product variant by attachment id. Get image ids from get_product under variants[].images."
    input_schema(
      properties: {
        slug: { type: "string" },
        variantId: { type: "string" },
        imageIds: { type: "array", items: { type: "string" } }
      },
      required: %w[slug variantId imageIds]
    )

    def self.call(slug:, variantId:, imageIds:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $variantId: ID!, $imageIds: [ID!]!) {
            removeVariantImages(slug: $slug, variantId: $variantId, imageIds: $imageIds) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, variantId: variantId, imageIds: imageIds }
      )
    end
  end
end
