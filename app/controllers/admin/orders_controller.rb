module Admin
  class OrdersController < BaseController
    before_action :set_order, only: %i[show update transition]

    def index
      @status = params[:status]
      @orders = current_store.orders.recent.includes(:customer)
      @orders = @orders.by_status(@status) if @status.present?
      if params[:q].present?
        q = "%#{Order.sanitize_sql_like(params[:q].strip)}%"
        @orders = @orders.where("number ILIKE :q OR customer_name ILIKE :q OR customer_phone ILIKE :q", q: q)
      end
    end

    def show
    end

    def update
      if @order.update(order_params)
        redirect_to admin_order_path(@order), notice: "Order updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def transition
      @order.transition_to!(params[:to_status], reason: params[:cancel_reason])
      redirect_to admin_order_path(@order), notice: "Order marked as #{params[:to_status]}."
    rescue ArgumentError, StandardError => e
      redirect_to admin_order_path(@order), alert: e.message
    end

    private

    def set_order
      @order = current_store.orders.find(params[:id])
    end

    def order_params
      params.require(:order).permit(:notes)
    end
  end
end
