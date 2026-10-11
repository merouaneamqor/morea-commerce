class CheckoutsController < ApplicationController
  include DeliveryRecall

  before_action :require_store!
  before_action :require_cart_items!

  def show
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
    @checkout = Checkout.new(
      delivery_recall_attributes(
        name: params[:name],
        phone: params[:phone],
        phone_country: params[:phone_country],
        city: params[:city],
        district: params[:district],
        address: params[:address],
        discount_code: params[:discount_code]
      ).merge(cart: @cart, store: current_store)
    )
  end

  def create
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
    @checkout = Checkout.new(checkout_params.merge(cart: @cart, store: current_store))

    if @checkout.valid?
      order = @checkout.place_order!
      remember_delivery_from_checkout!(@checkout)
      session.delete(:cart_token)
      session[:pixel_purchase_order_id] = order.id
      redirect_to order_path(order.number), notice: t("checkout.placed")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def checkout_params
    params.require(:checkout).permit(:name, :phone, :phone_country, :city, :district, :address, :notes, :discount_code)
  end

  def require_cart_items!
    return unless current_cart.empty?

    redirect_to cart_path, alert: t("checkout.errors.empty_cart")
  end
end
