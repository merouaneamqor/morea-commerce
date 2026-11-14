class OrdersController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :lookup,
    by: -> { "#{current_store.id}:#{request.remote_ip}" }

  def show
    @order = current_store.orders.includes(order_items: { product: { images_attachments: :blob } })
      .find_by!(id: session[:verified_order_id], number: params[:number])
    response.headers["Cache-Control"] = "private, no-store"
    @pixel_purchase = flash[:pixel_purchase_order_id].to_i == @order.id
  end

  def track
  end

  def lookup
    order = current_store.orders.find_by(number: params[:number].to_s.strip.upcase)
    if order && phone_matches?(order)
      session[:verified_order_id] = order.id
      redirect_to order_path(order.number), status: :see_other
    else
      redirect_to track_orders_path, alert: t("orders.not_found")
    end
  end

  private

  def phone_matches?(order)
    country = Phonelib.parse(order.customer_phone).country.presence || "MA"
    phone = Checkout.normalize_phone(params[:phone], country: country)
    phone.present? && phone == Checkout.normalize_phone(order.customer_phone, country: country)
  end
end
