# frozen_string_literal: true

module CatalogTools
  class GetOrder < MCP::Tool
    description "Get one delivery order by its number. Does not include phone, street address, or email."
    input_schema(
      properties: { number: { type: "string" } },
      required: [ "number" ]
    )

    def self.call(number:, server_context:)
      CatalogExecutor.call(
        store: server_context.fetch(:store),
        query: <<~GQL,
          query($number: String!) {
            order(number: $number) { #{CatalogExecutor::ORDER_FIELDS} }
          }
        GQL
        variables: { number: number }
      )
    end
  end
end
