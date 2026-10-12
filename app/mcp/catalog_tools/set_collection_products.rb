# frozen_string_literal: true

module CatalogTools
  class SetCollectionProducts < MCP::Tool
    description "Replace the products in a collection. Order is the display order. Pass an empty list to clear it."
    input_schema(
      properties: {
        slug: { type: "string" },
        productSlugs: { type: "array", items: { type: "string" } }
      },
      required: %w[slug productSlugs]
    )

    def self.call(slug:, productSlugs:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $productSlugs: [String!]!) {
            setCollectionProducts(slug: $slug, productSlugs: $productSlugs) {
              collection { #{CatalogExecutor::COLLECTION_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug, productSlugs: productSlugs }
      )
    end
  end
end
