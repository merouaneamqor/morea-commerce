# frozen_string_literal: true

module CatalogTools
  class CreateCollection < MCP::Tool
    description "Create a collection. Include a fr translation name."
    input_schema(
      properties: {
        translations: {
          type: "array",
          items: {
            type: "object",
            properties: {
              locale: { type: "string", enum: %w[fr en ar] },
              name: { type: "string" },
              subtitle: { type: "string" },
              description: { type: "string" }
            },
            required: %w[locale name]
          }
        },
        slug: { type: "string" },
        published: { type: "boolean" },
        position: { type: "integer" },
        productSlugs: { type: "array", items: { type: "string" } }
      },
      required: [ "translations" ]
    )

    def self.call(translations:, server_context:, **attrs)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($translations: [CollectionTranslationInput!]!, $slug: String, $published: Boolean, $position: Int, $productSlugs: [String!]) {
            createCollection(translations: $translations, slug: $slug, published: $published, position: $position, productSlugs: $productSlugs) {
              collection { #{CatalogExecutor::COLLECTION_FIELDS} }
              errors
            }
          }
        GQL
        variables: { translations: translations }.merge(attrs)
      )
    end
  end
end
