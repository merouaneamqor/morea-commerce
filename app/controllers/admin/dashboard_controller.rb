module Admin
  class DashboardController < BaseController
    def show
      @orders = current_store.orders
      @counts = Order::STATUSES.index_with { |s| @orders.by_status(s).count }
      @cancel_rate = @orders.cancel_rate
      @recent_orders = @orders.recent.limit(8)
      @low_stock = current_store.products.active.low_stock.includes(:product_variants)
    end
  end
end
