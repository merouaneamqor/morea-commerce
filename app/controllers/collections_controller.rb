class CollectionsController < ApplicationController
  SORTS = %w[featured price_asc price_desc newest].freeze

  def index
    @collections = current_store.collections.published.includes(:translations).order(:position)
  end

  def show
    @collection = current_store.collections.published.includes(:translations).find_by!(slug: params[:slug])
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "featured"
    @in_stock = params[:in_stock] == "1"

    products = @collection.products.active.includes(:translations, :product_variants, images_attachments: :blob)
    products =
      case @sort
      when "price_asc" then products.reorder(:price_cents)
      when "price_desc" then products.reorder(price_cents: :desc)
      when "newest" then products.reorder(created_at: :desc)
      else products.order("collection_products.position", :name)
      end
    @products = products.to_a
    @products.select!(&:available?) if @in_stock
  end
end
