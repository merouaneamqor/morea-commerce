class CheckoutsController < ApplicationController
  before_action :require_store!
  before_action :require_cart_items!

  def show
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
    @checkout = Checkout.new(
      name: params[:name],
      phone: params[:phone],
      city: params[:city],
      address: params[:address]
    )
  end

  def create
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
    @checkout = Checkout.new(checkout_params.merge(cart: @cart, store: current_store))

    if @checkout.valid?
      order = @checkout.place_order!
      session.delete(:cart_token)
      redirect_to order_path(order.number), notice: "Order confirmed. Pay on delivery."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def checkout_params
    params.require(:checkout).permit(:name, :phone, :city, :address, :notes)
  end

  def require_cart_items!
    return unless current_cart.empty?

    redirect_to cart_path, alert: "Your bag is empty."
  end
end
