# frozen_string_literal: true

module CatalogTools
  class GetCollection < MCP::Tool
    description "Get one collection by slug."
    input_schema(
      properties: { slug: { type: "string" } },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($slug: String!) {
            collection(slug: $slug) { #{CatalogExecutor::COLLECTION_FIELDS} }
          }
        GQL
        variables: { slug: slug }
      )
    end
  end
end
