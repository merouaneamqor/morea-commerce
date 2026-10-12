# frozen_string_literal: true

module CatalogTools
  class ProductStats < MCP::Tool
    description "Units, revenue, and stock for each product in a date window. Omit slug for every product. Revenue and units delivered use delivered_at. Placed, cancelled, and returned use orders created in the window. Variant rows include current stock."
    input_schema(
      properties: {
        slug: { type: "string" },
        since: { type: "string", description: "YYYY-MM-DD" },
        until: { type: "string", description: "YYYY-MM-DD" }
      }
    )

    def self.call(server_context:, slug: nil, since: nil, until: nil)
      finish = binding.local_variable_get(:until)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($since: ISO8601Date, $until: ISO8601Date, $slug: String) {
            productStats(since: $since, until: $until, slug: $slug) { #{CatalogExecutor::PRODUCT_STAT_FIELDS} }
          }
        GQL
        variables: { since: since, until: finish, slug: slug }.compact
      )
    end
  end
end
