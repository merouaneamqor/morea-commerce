class CartsController < ApplicationController
  before_action :require_store!

  def show
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
  end

  def add_item
    product = current_store.products.active.find(params[:product_id])
    variant = product.product_variants.active.find_by(id: params[:product_variant_id])
    quantity = params[:quantity].presence || 1
    current_cart.add_product!(product, quantity: quantity, variant: variant)

    return redirect_to(checkout_path) if params[:checkout].present?

    respond_to do |format|
      format.turbo_stream { render_drawer }
      format.html { redirect_to cart_path, notice: t("cart.added") }
    end
  end

  def update_item
    item = current_cart.cart_items.find(params[:item_id])
    item.update!(quantity: params[:quantity].to_i.clamp(1, 99))
    respond_from_drawer_or_redirect(t("cart.updated"))
  end

  def remove_item
    current_cart.cart_items.find(params[:item_id]).destroy!
    respond_from_drawer_or_redirect(t("cart.removed"))
  end

  private

  def respond_from_drawer_or_redirect(message)
    if params[:from] == "drawer" && request.format.turbo_stream?
      render_drawer
    else
      redirect_to cart_path, notice: message
    end
  end

  def render_drawer
    current_cart.cart_items.reset
    render turbo_stream: [
      turbo_stream.replace("cart-drawer", partial: "carts/drawer", locals: { cart: current_cart, open: true }),
      turbo_stream.replace("cart-count", partial: "carts/count")
    ]
  end
end
