# frozen_string_literal: true

class CatalogServer
  TOOLS = [
    CatalogTools::ReadCatalogGuide,
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
    CatalogTools::CancelOrder,
    CatalogTools::SetProductVariants,
    CatalogTools::DeleteProductVariants,
    CatalogTools::Storefront::GetStoreSettings,
    CatalogTools::Storefront::UpdateCheckout,
    CatalogTools::Storefront::UpdateMarketing,
    CatalogTools::Storefront::UpdateShipping,
    CatalogTools::Storefront::SyncShipping,
    CatalogTools::Storefront::InstallTheme,
    CatalogTools::Storefront::ListDiscounts,
    CatalogTools::Storefront::UpsertDiscount,
    CatalogTools::Storefront::DeleteDiscount,
    CatalogTools::Storefront::ListActiveCarts,
    CatalogTools::Storefront::ListAbandonedCarts,
    CatalogTools::Storefront::ListCustomers,
    CatalogTools::Storefront::GetCustomer,
    CatalogTools::Storefront::UpsertCustomer,
    CatalogTools::Storefront::ExportCsv,
    CatalogTools::Storefront::ImportCsv,
    CatalogTools::Storefront::ListHomeSections,
    CatalogTools::Storefront::UpsertHomeSection,
    CatalogTools::Storefront::DeleteHomeSection,
    CatalogTools::Storefront::ListPages,
    CatalogTools::Storefront::UpsertPage,
    CatalogTools::Storefront::DeletePage,
    CatalogTools::Storefront::ListMenuItems,
    CatalogTools::Storefront::UpsertMenuItem,
    CatalogTools::Storefront::DeleteMenuItem,
    CatalogTools::Autonomy::GetStoreProfile,
    CatalogTools::Autonomy::GetFullCatalog,
    CatalogTools::Autonomy::AuditStore,
    CatalogTools::Autonomy::GetProductSchema,
    CatalogTools::Autonomy::ValidateProduct,
    CatalogTools::Autonomy::SuggestCollectionStructure,
    CatalogTools::Autonomy::PreviewChangeset,
    CatalogTools::Autonomy::ApplyChangeset,
    CatalogTools::Autonomy::VerifyChangeset,
    CatalogTools::Autonomy::RollbackChangeset
  ].freeze

  def self.build(store:)
    MCP::Server.new(
      name: "morea",
      title: "Morea catalog",
      version: "1.0.0",
      website_url: store.origin,
      icons: icons_for(store),
      instructions: <<~TEXT.squish,
        You manage one Morea store. Prefer audit → plan → execute → verify for multi-product work.
        Start with get_store_profile, get_full_catalog or audit_store, then preview_changeset, apply_changeset, verify_changeset.
        Level 1 content fixes apply automatically. Level 2 (prices, slugs, structural collection changes) needs approveLevel2.
        Level 3 deletes need approveLevel3 and confirm: true. Use rollback_changeset when a bad apply must be undone.
        Create and update products directly for single edits. A missing MCP resource is not an error and must not block a write.
        A draft is create_product with status draft, stock 0, priceDh in whole currency units, a fr translation name, and collectionSlugs such as ["essentials"].
        The full manual is the tool read_catalog_guide. GraphQL { guide } returns the same text.
        Use store_stats, product_stats, list_orders, get_order, and cancel_order for strategy. Delivered revenue is cash collected.
        cancel_order needs confirm: true and only works before pickup.
        Checkout is cash on delivery. Shipping is Sendit. Coupons, customers, CSV, pixels, and the home page are their own tools. There is no card gateway, email campaign, or custom domain.
        coverUrl and the attached cover photo are the storefront image. Do not replace them with a web search.
        Prices are whole currency units (priceDh), not cents. Locales are fr, en, and ar; create with a fr name.
        Deletes require confirm: true. Images are base64 or a public http(s) URL (jpeg, png, webp, gif, 8MB, 4 per call).
        GraphQL is POST /graphql on this host with the same Bearer token. Query { guide } returns the same manual.
        Install that manual with npx skills add on this host. The file is /.well-known/agent-skills/morea-catalog/SKILL.md.
      TEXT
      tools: TOOLS,
      resources: [ CatalogGuideResource ],
      server_context: { store: store }
    )
  end

  def self.icons_for(store)
    base = store.origin
    [
      { src: "#{base}/icon-128.png", mime_type: "image/png", sizes: [ "128x128" ] },
      { src: "#{base}/icon-48.png", mime_type: "image/png", sizes: [ "48x48" ] }
    ]
  end
end
