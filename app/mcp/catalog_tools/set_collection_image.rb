# frozen_string_literal: true

module CatalogTools
  class SetCollectionImage < MCP::Tool
    description "Set or replace a collection cover image. Pass base64 (raw or data-URL) or a public http(s) URL. jpeg, png, webp, or gif, up to 8MB."
    input_schema(
      properties: {
        slug: { type: "string" },
        base64: { type: "string" },
        url: { type: "string" },
        filename: { type: "string" },
        contentType: { type: "string", enum: %w[image/jpeg image/png image/webp image/gif] }
      },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:, **attrs)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $image: ImageUploadInput!) {
            setCollectionImage(slug: $slug, image: $image) {
              collection { #{CatalogExecutor::COLLECTION_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, image: attrs }
      )
    end
  end
end
