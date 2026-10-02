module Admin
  class OrdersController < BaseController
    before_action :set_order, only: %i[show update transition sendit sendit_label]

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

    # Send / retry / refresh / cancel the Sendit parcel for one order
    def sendit
      return redirect_to(admin_order_path(@order), alert: "Sendit is not configured.") unless Sendit::Client.configured?

      if params[:district_id].present?
        district = Sendit::Districts.find(params[:district_id])
        @order.update!(sendit_district_id: district&.dig(:id), sendit_district_name: district&.dig(:name))
      end

      sync = Sendit::Sync.new(@order)
      case params[:op]
      when "cancel" then sync.cancel!
      when "refresh" then sync.refresh!
      else sync.push!
      end

      if @order.reload.sendit_error.present?
        redirect_to admin_order_path(@order), alert: "Sendit: #{@order.sendit_error}"
      else
        redirect_to admin_order_path(@order), notice: "Sendit: parcel #{@order.sendit_code} — #{@order.sendit_label}."
      end
    end

    def sendit_label
      url = Sendit::Sync.new(@order).label_url
      url.present? ? redirect_to(url, allow_other_host: true) : redirect_to(admin_order_path(@order), alert: "No Sendit label yet.")
    rescue Sendit::Client::Error => e
      redirect_to admin_order_path(@order), alert: "Sendit: #{e.message}"
    end

    def sendit_sync_all
      return redirect_to(admin_orders_path, alert: "Sendit is not configured.") unless Sendit::Client.configured?

      count = Sendit::Sync.enqueue_all(current_store.orders)
      redirect_to admin_orders_path, notice: "Syncing #{count} orders with Sendit in the background."
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
