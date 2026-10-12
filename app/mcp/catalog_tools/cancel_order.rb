# frozen_string_literal: true

module CatalogTools
  class CancelOrder < MCP::Tool
    description "Cancel one delivery order by its number before the courier picks it up. Requires confirm: true. Optional reason is stored on the order. Restores reserved stock and deletes a Sendit parcel that has not left the warehouse."
    input_schema(
      properties: {
        number: { type: "string" },
        confirm: { type: "boolean", description: "Must be true" },
        reason: { type: "string" }
      },
      required: %w[number confirm]
    )

    def self.call(number:, confirm:, server_context:, reason: nil)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          mutation($number: String!, $confirm: Boolean!, $reason: String) {
            cancelOrder(number: $number, confirm: $confirm, reason: $reason) {
              order { #{CatalogExecutor::ORDER_FIELDS} }
              errors
            }
          }
        GQL
        variables: { number: number, confirm: confirm, reason: reason }.compact
      )
    end
  end
end
