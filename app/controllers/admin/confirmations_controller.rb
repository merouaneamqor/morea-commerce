module Admin
  class ConfirmationsController < BaseController
    before_action :require_store_context!

    def index
      @page = params[:page].to_i.clamp(1, 100_000)
      @filter = %w[available mine all callbacks_due].include?(params[:filter]) ? params[:filter] : "available"
      orders = current_store.orders.active.where(status: "new", sendit_code: [ nil, "" ])
        .joins("LEFT JOIN order_confirmations ON order_confirmations.order_id = orders.id")
      if @filter == "mine"
        orders = orders.where(order_confirmations: { assigned_user_id: current_user.id })
      elsif @filter == "callbacks_due"
        orders = orders.where(order_confirmations: { store_id: current_store.id, disposition: "callback" })
          .where("order_confirmations.callback_at <= ?", Time.current)
      elsif @filter == "available"
        orders = orders.where("order_confirmations.assigned_user_id IS NULL")
          .where("order_confirmations.callback_at IS NULL OR order_confirmations.callback_at <= ?", Time.current)
      end
      @orders = orders.order(Arel.sql("order_confirmations.callback_at ASC NULLS LAST, orders.created_at ASC, orders.id ASC"))
        .offset((@page - 1) * 50).limit(51).to_a
      @has_next = @orders.length > 50
      @orders = @orders.first(50)
      @confirmations = OrderConfirmation.where(store: current_store, order_id: @orders.map(&:id)).includes(:assigned_user)
        .index_by(&:order_id)
      @attempt_counts = ConfirmationAttempt.joins(:order_confirmation)
        .where(store: current_store, order_confirmations: { order_id: @orders.map(&:id) })
        .group("order_confirmations.order_id").count
    end

    def claim
      desk.claim(params[:order_id])
      redirect_to admin_confirmations_path(filter: "mine"), notice: t("admin.confirmations.claimed")
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid => e
      redirect_to admin_confirmations_path, alert: e.message
    end

    def release
      desk.release(params[:order_id])
      redirect_to admin_confirmations_path(filter: "mine"), notice: t("admin.confirmations.released")
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid => e
      redirect_to admin_confirmations_path(filter: "mine"), alert: e.message
    end

    def outcome
      desk.record(params[:order_id], outcome: params[:outcome], notes: params[:notes], callback_at: params[:callback_at])
      redirect_to admin_confirmations_path(filter: "mine"), notice: t("admin.confirmations.recorded")
    rescue Confirmations::Desk::Error, ArgumentError => e
      redirect_to admin_confirmations_path(filter: "mine"), alert: e.message
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    def desk
      Confirmations::Desk.new(store: current_store, user: current_user)
    end
  end
end
