module Admin
  class CustomersController < BaseController
    def index
      @customers = current_store.customers.order(orders_count: :desc, created_at: :desc)
    end

    def show
      @customer = current_store.customers.find(params[:id])
      @orders = @customer.orders.recent
    end
  end
end
