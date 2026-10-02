class HomeController < ApplicationController
  def index
    @store = current_store
    @store&.translations&.load if @store
    @featured = @store&.featured_product || @store&.products&.active&.featured&.first || @store&.products&.active&.first
    @collection = @store&.featured_collection || @store&.collections&.published&.first
    @collection_products =
      if @collection
        @collection.products.active.includes(:translations).limit(4)
      else
        Product.none
      end
    @collection_tiles = collection_tiles
    @manifesto_image = public_image_url("editorial/manifesto.jpg")
    @campaign_target =
      if @featured
        product_path(@featured)
      elsif @collection
        collection_path(@collection)
      else
        collections_path
      end
  end

  private

  # One tile per collection: editorial cover if present, else a product not already used
  def collection_tiles
    return [] unless @store

    used = []
    @store.collections.published.order(:position).includes(:translations).limit(3).filter_map do |collection|
      cover_url = public_image_url("collections/#{collection.slug}/cover.jpg")
      unless cover_url
        products = collection.products.active.to_a
        product = products.find { |p| used.exclude?(p.id) } || products.first
        next unless product

        used << product.id
        cover_url = helpers.product_image_url(product)
      end

      [collection, cover_url]
    end
  end

  def public_image_url(path)
    "/images/#{path}" if Rails.root.join("public/images", path).exist?
  end
end
