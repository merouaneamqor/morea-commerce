# frozen_string_literal: true

module CatalogTools
  class ListCollections < MCP::Tool
    description "List collections in the authenticated store."
    input_schema(
      properties: {
        published: { type: "boolean" },
        limit: { type: "integer", description: "1-100, default 50" }
      }
    )

    def self.call(server_context:, published: nil, limit: nil)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($published: Boolean, $limit: Int) {
            collections(published: $published, limit: $limit) { #{CatalogExecutor::COLLECTION_FIELDS} }
          }
        GQL
        variables: { published: published, limit: limit }.compact
      )
    end
  end
end
