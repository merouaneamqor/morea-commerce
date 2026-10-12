# frozen_string_literal: true

module CatalogTools
  class ListOrders < MCP::Tool
    description "List delivery orders. Optional status, city, and YYYY-MM-DD since/until on the date the order was placed. Does not include phone, street address, or email."
    input_schema(
      properties: {
        status: {
          type: "string",
          enum: %w[new confirmed preparing awaiting_pickup picked_up in_transit out_for_delivery delivered unreachable postponed address_issue cancelled returned]
        },
        city: { type: "string" },
        since: { type: "string", description: "YYYY-MM-DD" },
        until: { type: "string", description: "YYYY-MM-DD" },
        limit: { type: "integer", description: "1-100, default 50" }
      }
    )

    def self.call(server_context:, status: nil, city: nil, since: nil, until: nil, limit: nil)
      finish = binding.local_variable_get(:until)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($status: String, $city: String, $since: ISO8601Date, $until: ISO8601Date, $limit: Int) {
            orders(status: $status, city: $city, since: $since, until: $until, limit: $limit) { #{CatalogExecutor::ORDER_FIELDS} }
          }
        GQL
        variables: { status: status, city: city, since: since, until: finish, limit: limit }.compact
      )
    end
  end
end
