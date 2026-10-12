module Admin
  class CartsController < BaseController
    def index
      @view = params[:view] == "abandoned" ? "abandoned" : "active"
      scope = @view == "abandoned" ? current_store.carts.stale : current_store.carts.recent
      @carts = scope.includes(cart_items: { product: :translations, product_variant: [] }).limit(100)
    end

    def show
      @cart = current_store.carts.includes(cart_items: { product: :translations, product_variant: [] }).find(params[:id])
    end
  end
end
