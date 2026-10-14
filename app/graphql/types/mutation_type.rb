# frozen_string_literal: true

module Types
  class MutationType < BaseObject
    field :create_product, mutation: Mutations::CreateProduct
    field :update_product, mutation: Mutations::UpdateProduct
    field :delete_product, mutation: Mutations::DeleteProduct
    field :create_collection, mutation: Mutations::CreateCollection
    field :update_collection, mutation: Mutations::UpdateCollection
    field :delete_collection, mutation: Mutations::DeleteCollection
    field :set_collection_products, mutation: Mutations::SetCollectionProducts
    field :set_product_collections, mutation: Mutations::SetProductCollections
    field :add_product_images, mutation: Mutations::AddProductImages
    field :remove_product_images, mutation: Mutations::RemoveProductImages
    field :reorder_product_images, mutation: Mutations::ReorderProductImages
    field :set_collection_image, mutation: Mutations::SetCollectionImage
    field :remove_collection_image, mutation: Mutations::RemoveCollectionImage
    field :set_product_variants, mutation: Mutations::SetProductVariants
    field :delete_product_variants, mutation: Mutations::DeleteProductVariants
    field :cancel_order, mutation: Mutations::CancelOrder
    field :adjust_stock, mutation: Mutations::AdjustStock
    field :set_stock, mutation: Mutations::SetStock
    field :update_checkout, mutation: Mutations::Storefront::UpdateCheckout
    field :update_marketing, mutation: Mutations::Storefront::UpdateMarketing
    field :update_shipping, mutation: Mutations::Storefront::UpdateShipping
    field :sync_shipping, mutation: Mutations::Storefront::SyncShipping
    field :install_theme, mutation: Mutations::Storefront::InstallTheme
    field :upsert_discount, mutation: Mutations::Storefront::UpsertDiscount
    field :delete_discount, mutation: Mutations::Storefront::DeleteDiscount
    field :upsert_customer, mutation: Mutations::Storefront::UpsertCustomer
    field :import_csv, mutation: Mutations::Storefront::ImportCsv
    field :upsert_home_section, mutation: Mutations::Storefront::UpsertHomeSection
    field :delete_home_section, mutation: Mutations::Storefront::DeleteHomeSection
    field :upsert_page, mutation: Mutations::Storefront::UpsertPage
    field :delete_page, mutation: Mutations::Storefront::DeletePage
    field :upsert_menu_item, mutation: Mutations::Storefront::UpsertMenuItem
    field :delete_menu_item, mutation: Mutations::Storefront::DeleteMenuItem
    field :preview_changeset, mutation: Mutations::Autonomy::PreviewChangeset
    field :apply_changeset, mutation: Mutations::Autonomy::ApplyChangeset
    field :verify_changeset, mutation: Mutations::Autonomy::VerifyChangeset
    field :rollback_changeset, mutation: Mutations::Autonomy::RollbackChangeset
    field :update_store_profile, mutation: Mutations::Autonomy::UpdateStoreProfile
    field :reorder_home_sections, mutation: Mutations::Builders::ReorderHomeSections
    field :set_home_layout, mutation: Mutations::Builders::SetHomeLayout
    field :upsert_landing_page, mutation: Mutations::Builders::UpsertLandingPage
    field :delete_landing_page, mutation: Mutations::Builders::DeleteLandingPage
    field :upsert_landing_section, mutation: Mutations::Builders::UpsertLandingSection
    field :delete_landing_section, mutation: Mutations::Builders::DeleteLandingSection
    field :reorder_landing_sections, mutation: Mutations::Builders::ReorderLandingSections
    field :set_landing_layout, mutation: Mutations::Builders::SetLandingLayout
  end
end
