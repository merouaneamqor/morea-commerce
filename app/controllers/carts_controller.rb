class CartsController < ApplicationController
  before_action :require_store!

  def show
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
  end

  def add_item
    product = current_store.products.active.find(params[:product_id])
    variant = product.product_variants.active.find_by(id: params[:product_variant_id])
    quantity = [ params[:quantity].to_i, 1 ].max
    current_cart.add_product!(product, quantity: quantity, variant: variant)

    return redirect_to(checkout_path) if params[:checkout].present?

    pixel_event = if current_store.pixels_configured?
      {
        name: "AddToCart",
        payload: {
          content_ids: [ product.id.to_s ],
          content_type: "product",
          content_name: product.name,
          value: (product.price_cents.to_i / 100.0 * quantity).round(2),
          currency: current_store.pixel_currency,
          quantity: quantity
        }
      }
    end

    respond_to do |format|
      format.turbo_stream { render_drawer(pixel_event: pixel_event) }
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

  def render_drawer(pixel_event: nil)
    current_cart.cart_items.reset
    streams = [
      turbo_stream.replace("cart-drawer", partial: "carts/drawer", locals: { cart: current_cart, open: true }),
      turbo_stream.replace("cart-count", partial: "carts/count")
    ]
    if pixel_event
      streams << turbo_stream.append(
        "pixel-events",
        partial: "shared/pixel_event",
        locals: { name: pixel_event[:name], payload: pixel_event[:payload] }
      )
    end
    render turbo_stream: streams
  end
end
