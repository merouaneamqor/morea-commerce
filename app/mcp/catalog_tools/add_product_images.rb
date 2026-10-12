# frozen_string_literal: true

module CatalogTools
  class AddProductImages < MCP::Tool
    description "Attach images to a product. Each image is base64 (raw or data-URL) or a public http(s) URL. New images are appended. Up to 4 images, 8MB each. jpeg, png, webp, or gif."
    input_schema(
      properties: {
        slug: { type: "string" },
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
      required: %w[slug images]
    )

    def self.call(slug:, images:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $images: [ImageUploadInput!]!) {
            addProductImages(slug: $slug, images: $images) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, images: images }
      )
    end
  end
end
