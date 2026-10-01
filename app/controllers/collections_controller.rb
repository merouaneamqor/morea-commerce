class CollectionsController < ApplicationController
  def index
    @collections = current_store.collections.published.includes(:translations)
  end

  def show
    @collection = current_store.collections.published.includes(:translations).find_by!(slug: params[:slug])
    @products = @collection.products.active.includes(:translations).order("collection_products.position", :name).limit(6)
  end
end
