# frozen_string_literal: true

class CatalogGuideResource < MCP::Resource
  uri "morea://catalog"
  resource_name "catalog"
  title "Morea catalog guide"
  description "Read this before writing. Rules for products, collections, prices, translations, and images, plus GraphQL examples."
  mime_type "text/markdown"

  def self.contents(server_context: nil)
    MCP::Resource::TextContents.new(
      text: CatalogGuide.text,
      uri: uri,
      mime_type: mime_type
    )
  end
end
