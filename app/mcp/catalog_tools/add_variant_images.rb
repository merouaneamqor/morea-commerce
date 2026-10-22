# frozen_string_literal: true

module CatalogTools
  class AddVariantImages < MCP::Tool
    description "Attach images to a product variant. Use variantId from get_product or set_product_variants. New images are appended; up to 4 images, 8MB each."
    input_schema(
      properties: {
        slug: { type: "string" },
        variantId: { type: "string" },
        images: {
          type: "array",
          items: {
            type: "object",
            properties: {
              base64: { type: "string", description: "Raw or data-URL base64" },
              url: { type: "string", description: "Public http(s) image URL" },
              filename: { type: "string" },
              contentType: { type: "string", enum: %w[image/jpeg image/png image/webp image/gif] }
            }
          }
        }
      },
      required: %w[slug variantId images]
    )

    def self.call(slug:, variantId:, images:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $variantId: ID!, $images: [ImageUploadInput!]!) {
            addVariantImages(slug: $slug, variantId: $variantId, images: $images) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, variantId: variantId, images: images }
      )
    end
  end
end
