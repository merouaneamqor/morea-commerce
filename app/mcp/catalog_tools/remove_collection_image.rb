# frozen_string_literal: true

module CatalogTools
  class RemoveCollectionImage < MCP::Tool
    description "Remove a collection cover image."
    input_schema(
      properties: { slug: { type: "string" } },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!) {
            removeCollectionImage(slug: $slug) {
              collection { #{CatalogExecutor::COLLECTION_FIELDS} }
              errors
            }
          }
        GQL
        variables: { slug: slug }
      )
    end
  end
end
