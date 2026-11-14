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

    def self.call(server_context:, **arguments)
      CatalogExecutor.call(
        store: CatalogExecutor.store_from(server_context),
        query: <<~GQL,
          query($since: ISO8601Date, $until: ISO8601Date, $slug: String) {
            productStats(since: $since, until: $until, slug: $slug) { #{CatalogExecutor::PRODUCT_STAT_FIELDS} }
          }
        GQL
        variables: {
          since: arguments[:since],
          until: arguments[:until],
          slug: arguments[:slug]
        }.compact,
        include_covers: false
      )
    end
  end
end
