class OrdersController < ApplicationController
  def show
    @order = current_store.orders.find_by!(number: params[:number])
  end

  def track
  end

  def lookup
    order = current_store.orders.find_by(number: params[:number].to_s.strip.upcase)
    if order && order.customer_phone.to_s.gsub(/[^\d]/, "").end_with?(params[:phone].to_s.gsub(/[^\d]/, "").last(8))
      redirect_to order_path(order.number)
    else
      redirect_to track_orders_path, alert: t("orders.not_found")
    end
  end
end
