# frozen_string_literal: true

module CatalogTools
  class SetProductCollections < MCP::Tool
    description "Replace the collections a product belongs to. Pass an empty list to remove it from all collections."
    input_schema(
      properties: {
        slug: { type: "string" },
        collectionSlugs: { type: "array", items: { type: "string" } }
      },
      required: %w[slug collectionSlugs]
    )

    def self.call(slug:, collectionSlugs:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $collectionSlugs: [String!]!) {
            setProductCollections(slug: $slug, collectionSlugs: $collectionSlugs) {
              product { #{CatalogExecutor::PRODUCT_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, collectionSlugs: collectionSlugs }
      )
    end
  end
end
