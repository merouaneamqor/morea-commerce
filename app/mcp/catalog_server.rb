# frozen_string_literal: true

class CatalogServer
  TOOLS = [
    CatalogTools::ListProducts,
    CatalogTools::GetProduct,
    CatalogTools::CreateProduct,
    CatalogTools::UpdateProduct,
    CatalogTools::DeleteProduct,
    CatalogTools::ListCollections,
    CatalogTools::GetCollection,
    CatalogTools::CreateCollection,
    CatalogTools::UpdateCollection,
    CatalogTools::DeleteCollection,
    CatalogTools::SetCollectionProducts,
    CatalogTools::SetProductCollections,
    CatalogTools::AddProductImages,
    CatalogTools::RemoveProductImages,
    CatalogTools::ReorderProductImages,
    CatalogTools::SetCollectionImage,
    CatalogTools::RemoveCollectionImage,
    CatalogTools::StoreStats,
    CatalogTools::ProductStats,
    CatalogTools::ListOrders,
    CatalogTools::GetOrder,
    CatalogTools::SetProductVariants,
    CatalogTools::DeleteProductVariants
  ].freeze

  def self.build(store:)
    MCP::Server.new(
      name: "morea",
      title: "Morea catalog",
      version: "1.0.0",
      instructions: <<~TEXT.squish,
        You manage one Morea store's products, collections, variants, and delivery numbers. Read the resource morea://catalog before the first write.
        Use store_stats, product_stats, list_orders, and get_order for strategy. Delivered revenue is cash collected.
        coverUrl and the attached cover photo are the storefront image. Do not replace them with a web search.
        Prices are whole currency units (priceDh), not cents. Locales are fr, en, and ar; create with a fr name.
        Deletes require confirm: true. Images are base64 or a public http(s) URL (jpeg, png, webp, gif, 8MB, 4 per call).
        GraphQL is POST /graphql on this host with the same Bearer token. Query { guide } returns the same manual.
      TEXT
      tools: TOOLS,
      resources: [ CatalogGuideResource ],
      server_context: { store: store }
    )
  end
end
