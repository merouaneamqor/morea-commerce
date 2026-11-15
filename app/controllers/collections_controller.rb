class CollectionsController < ApplicationController
  include StorefrontCatalogFilters

  PER_PAGE = 24

  def index
    @collections = current_store.collections.published.includes(:translations).order(:position)
  end

  def show
    @collection = current_store.collections.published.includes(:translations).find_by!(slug: params[:slug])
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "featured"
    @in_stock = params[:in_stock] == "1"
    @page = [ params[:page].to_i, 1 ].max

    products = @collection.products.active.includes(:translations, :product_variants, images_attachments: :blob)
    products = apply_stock_filter(products) if @in_stock
    products = apply_catalog_sort(products, sort: @sort)

    @total_count = products.unscope(:order, :includes, :preload, :eager_load).distinct.count("products.id")
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = [ @page, @total_pages ].min
    @products = products
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE)
      .to_a
  end
end
