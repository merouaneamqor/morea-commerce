module Admin
  class CustomersController < BaseController
    before_action :set_customer, only: %i[show edit update]

    def index
      @customers = current_store.customers.order(orders_count: :desc, created_at: :desc)
      if params[:q].present?
        q = "%#{Customer.sanitize_sql_like(params[:q].strip)}%"
        @customers = @customers.where("name ILIKE :q OR phone ILIKE :q OR email ILIKE :q OR city ILIKE :q", q: q)
      end
    end

    def show
      @orders = @customer.orders.recent
      @addresses = @customer.addresses.order(default: :desc, created_at: :desc)
    end

    def edit
    end

    def update
      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: "Customer updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_customer
      @customer = current_store.customers.find(params[:id])
    end

    def customer_params
      params.require(:customer).permit(:name, :email, :phone, :city)
    end
  end
end
