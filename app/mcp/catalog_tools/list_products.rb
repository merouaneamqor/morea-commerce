# frozen_string_literal: true

module CatalogTools
  class ListProducts < MCP::Tool
    description "List products in the authenticated store. Optional search and status filter. Includes all image URLs per product and up to 8 attached cover previews. Use get_product to inspect gallery photos."
    input_schema(
      properties: {
        query: { type: "string", description: "Search name or slug" },
        status: { type: "string", enum: %w[draft active archived] },
        limit: { type: "integer", description: "1-100, default 50" }
      }
    )

    def self.call(server_context:, query: nil, status: nil, limit: nil)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($query: String, $status: String, $limit: Int) {
            products(query: $query, status: $status, limit: $limit) { #{CatalogExecutor::PRODUCT_FIELDS} }
          }
        GQL
        variables: compact(query:, status:, limit:)
      )
    end

    def self.compact(**values)
      values.compact
    end
  end
end
