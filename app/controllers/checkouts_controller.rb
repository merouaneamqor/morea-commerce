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
      district: params[:district],
      address: params[:address],
      discount_code: params[:discount_code],
      cart: @cart,
      store: current_store
    )
  end

  def create
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
    @checkout = Checkout.new(checkout_params.merge(cart: @cart, store: current_store))

    if @checkout.valid?
      order = @checkout.place_order!
      session.delete(:cart_token)
      redirect_to order_path(order.number), notice: t("checkout.placed")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def checkout_params
    params.require(:checkout).permit(:name, :phone, :city, :district, :address, :notes, :discount_code)
  end

  def require_cart_items!
    return unless current_cart.empty?

    redirect_to cart_path, alert: t("checkout.errors.empty_cart")
  end
end
