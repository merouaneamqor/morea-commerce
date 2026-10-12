# frozen_string_literal: true

module CatalogTools
  class StoreStats < MCP::Tool
    description "Store analytics for strategy. since and until are YYYY-MM-DD, default the last 30 days, max 366 days. Delivered revenue is cash collected. Placed revenue still includes orders that can be cancelled. Pipeline is the current status counts, not limited to the window."
    input_schema(
      properties: {
        since: { type: "string", description: "YYYY-MM-DD" },
        until: { type: "string", description: "YYYY-MM-DD" }
      }
    )

    def self.call(server_context:, since: nil, until: nil)
      finish = binding.local_variable_get(:until)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($since: ISO8601Date, $until: ISO8601Date) {
            stats(since: $since, until: $until) { #{CatalogExecutor::STATS_FIELDS} }
          }
        GQL
        variables: { since: since, until: finish }.compact
      )
    end
  end
end
