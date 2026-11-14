# frozen_string_literal: true

module CatalogTools
  class GetProduct < MCP::Tool
    description "Get one product by slug with all image URLs and up to 8 attached cover/gallery image previews. Each preview identifies its product and image URL."
    input_schema(
      properties: { slug: { type: "string" } },
      required: [ "slug" ]
    )

    def self.call(slug:, server_context:)
      CatalogExecutor.call(
        store: CatalogExecutor.store_from(server_context),
        query: <<~GQL,
          query($slug: String!) {
            product(slug: $slug) { #{CatalogExecutor::PRODUCT_FIELDS} }
          }
        GQL
        variables: { slug: slug }
      )
    end
  end
end
