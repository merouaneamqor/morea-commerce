module Admin
  class ConfirmationsController < BaseController
    PERIODS = %w[today week month].freeze
    REMINDER_COOLDOWN = 10.minutes
    REMINDER_MAX_LENGTH = 120
    FILTERS = %w[available mine all callbacks_due].freeze

    before_action :require_store_context!
    helper_method :agent_view?

    def index
      @page = params[:page].to_i.clamp(1, 100_000)
      @filters = agent_view? ? FILTERS - %w[all] : FILTERS
      @filter = @filters.include?(params[:filter]) ? params[:filter] : "available"
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
      @orders = orders.includes(:order_items).order(Arel.sql("order_confirmations.callback_at ASC NULLS LAST, orders.created_at ASC, orders.id ASC"))
        .offset((@page - 1) * 50).limit(51).to_a
      @has_next = @orders.length > 50
      @orders = @orders.first(50)
      @confirmations = OrderConfirmation.where(store: current_store, order_id: @orders.map(&:id)).includes(:assigned_user)
        .index_by(&:order_id)
      @attempt_counts = ConfirmationAttempt.joins(:order_confirmation)
        .where(store: current_store, order_confirmations: { order_id: @orders.map(&:id) })
        .group("order_confirmations.order_id").count
    end

    def home
      @home = Confirmations::AgentHome.new(store: current_store, user: current_user, range: period_range("today"))
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
    end

    def dashboard
      @period = period_param
      @performance = Confirmations::Performance.new(store: current_store, range: period_range(@period),
        only: (current_user if agent_view?))
      @rows = @performance.rows
      @totals = @performance.totals
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
    end

    def clock_in
      Confirmations::Shifts.new(store: current_store, user: current_user).clock_in
      redirect_to dashboard_admin_confirmations_path(period: period_param), notice: t("admin.confirmations.clocked_in")
    rescue Confirmations::Shifts::Error => e
      redirect_to dashboard_admin_confirmations_path(period: period_param), alert: e.message
    end

    def clock_out
      Confirmations::Shifts.new(store: current_store, user: current_user).clock_out
      redirect_to dashboard_admin_confirmations_path(period: period_param), notice: t("admin.confirmations.clocked_out")
    rescue Confirmations::Shifts::Error => e
      redirect_to dashboard_admin_confirmations_path(period: period_param), alert: e.message
    end

    # Agents are confined to this controller, so admin rights are checked here.
    def remind
      return head(:forbidden) unless current_user.admin? || current_user.super_admin?

      cooldown_key = "confirmation-reminder/#{current_store.id}"
      unless Rails.cache.write(cooldown_key, current_user.id, expires_in: REMINDER_COOLDOWN, unless_exist: true)
        return redirect_to admin_confirmations_path, alert: t("admin.confirmations.remind_cooldown")
      end

      message = params[:message].to_s.squish.first(REMINDER_MAX_LENGTH).presence || t("admin.confirmations.remind_default")
      sent = Notifications::AgentReminder.new(store: current_store, message: message).deliver
      # Nothing reached an agent, so let the next attempt go through immediately.
      Rails.cache.delete(cooldown_key) if sent.zero?

      if sent.zero?
        redirect_to admin_confirmations_path, alert: t("admin.confirmations.remind_none")
      else
        redirect_to admin_confirmations_path, notice: t("admin.confirmations.remind_sent", count: sent)
      end
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

    def agent_view?
      current_user.confirmation_agent_view?
    end

    def period_param
      PERIODS.include?(params[:period]) ? params[:period] : "today"
    end

    def period_range(period)
      now = Time.current
      case period
      when "week" then (now.beginning_of_day - 6.days)..now
      when "month" then (now.beginning_of_day - 29.days)..now
      else now.beginning_of_day..now
      end
    end

    def desk
      Confirmations::Desk.new(store: current_store, user: current_user)
    end
  end
end
