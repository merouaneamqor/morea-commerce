# frozen_string_literal: true

module CatalogTools
  class UpdateCollection < MCP::Tool
    description "Update a collection by slug. Omitted fields stay unchanged. newSlug renames it."
    input_schema(
      properties: {
        slug: { type: "string" },
        newSlug: { type: "string" },
        published: { type: "boolean" },
        position: { type: "integer" },
        translations: { type: "array", items: { type: "object" } }
      },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:, **attrs)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $newSlug: String, $published: Boolean, $position: Int, $translations: [CollectionTranslationInput!]) {
            updateCollection(slug: $slug, newSlug: $newSlug, published: $published, position: $position, translations: $translations) {
              collection { #{CatalogExecutor::COLLECTION_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug }.merge(attrs)
      )
    end
  end
end
