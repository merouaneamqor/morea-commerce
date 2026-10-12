# frozen_string_literal: true

module CatalogTools
  class ReadCatalogGuide < MCP::Tool
    description "Return the Morea operating manual. Use it for detailed rules. A missing MCP resource is not a reason to skip a write."

    def self.call(server_context:)
      server_context.fetch(:store)
      MCP::Tool::Response.new([ { type: "text", text: CatalogGuide.text } ])
    end
  end
end
