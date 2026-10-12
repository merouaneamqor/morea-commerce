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
  end
end
