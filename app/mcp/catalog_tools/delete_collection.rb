# frozen_string_literal: true

module CatalogTools
  class DeleteCollection < MCP::Tool
    description "Delete a collection by slug. Requires confirm: true."
    input_schema(
      properties: {
        slug: { type: "string" },
        confirm: { type: "boolean", description: "Must be true" }
      },
      required: %w[slug confirm]
    )

    def self.call(slug:, confirm:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($slug: String!, $confirm: Boolean!) {
            deleteCollection(slug: $slug, confirm: $confirm) { deleted errors }
          }
        GQL
        variables: { slug: slug, confirm: confirm }
      )
    end
  end
end
