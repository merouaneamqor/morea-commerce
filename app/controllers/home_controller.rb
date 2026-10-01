class HomeController < ApplicationController
  def index
    @store = current_store
    @store&.translations&.load if @store
    @featured = @store&.featured_product || @store&.products&.active&.featured&.first || @store&.products&.active&.first
    @collection = @store&.featured_collection || @store&.collections&.published&.first
    @collection_products =
      if @collection
        @collection.products.active.includes(:translations).limit(3)
      else
        Product.none
      end
    @campaign_target =
      if @collection
        collection_path(@collection)
      elsif @featured
        product_path(@featured)
      else
        collections_path
      end
  end
end
