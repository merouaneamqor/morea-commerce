module Admin
  class ConfirmationsController < BaseController
    PERIODS = %w[today week month].freeze
    FILTERS = %w[available mine all callbacks_due].freeze

    include DateRangeSelection

    before_action :require_store_context!
    helper_method :agent_view?

    # The call center page: stat cards, filters, tabs and the order table, all from Confirmations::CallCenter.
    def center
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
      @needs_clock_in = agent_view? && @open_shift.nil?
      @date_range = selected_date_range(scope: "call_center", default: "last_30")
      filters = params.permit(:tab, :product, :source, :whatsapp, :missed, :q, :sort, :page).to_h.symbolize_keys
      @center = Confirmations::CallCenter.new(store: current_store, user: current_user, range: @date_range.time_range, params: filters)
      @summary = Team::AgentEarnings.new(store: current_store, range: @date_range.time_range).summary_for(current_user) if agent_view?
    end

    def index
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
      @needs_clock_in = agent_view? && @open_shift.nil?
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
          .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition NOT IN ('wrong_number', 'blocked')")
          .where("order_confirmations.callback_at IS NULL OR order_confirmations.callback_at <= ?", Time.current)
        # An agent does not see what is attributed to a colleague; owners and supervisors see everything.
        orders = orders.where(agent_queue_condition, current_user.id) if agent_view?
      end
      @orders = orders.includes(:order_items).order(Arel.sql("order_confirmations.callback_at ASC NULLS LAST, orders.created_at ASC, orders.id ASC"))
        .offset((@page - 1) * 50).limit(51).to_a
      @has_next = @orders.length > 50
      @orders = @orders.first(50)
      @focus = agent_focus if agent_view?
      counted_ids = @orders.map(&:id)
      counted_ids << @focus.id if @focus
      @confirmations = OrderConfirmation.where(store: current_store, order_id: counted_ids).includes(:assigned_user)
        .index_by(&:order_id)
      @attempt_counts = ConfirmationAttempt.joins(:order_confirmation)
        .where(store: current_store, order_confirmations: { order_id: counted_ids })
        .group("order_confirmations.order_id").count
    end

    def home
      @home = Confirmations::AgentHome.new(store: current_store, user: current_user, range: period_range("today"))
      @presence_seconds = Confirmations::Presence.new(store: current_store, user: current_user).seconds_within(period_range("today")) if agent_view?
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
    end

    # "Attributions": the orders waiting for a call and who they are for, with the agents' load. Owners and supervisors only.
    def assignments
      return head(:forbidden) if agent_view?

      @assignments = Confirmations::Assignments.new(store: current_store, user: current_user, params: assignment_params)
    end

    def assign
      return head(:forbidden) if agent_view?

      agent = Confirmations::Assignments.new(store: current_store, user: current_user).assign!(params[:order_id], params[:agent_id], by: current_user)
      redirect_back_or_to assignments_admin_confirmations_path, notice: (agent ? t("call_assignments.assigned", name: agent.name.presence || agent.email) : t("call_assignments.unassigned"))
    rescue Confirmations::Assignments::Error => e
      redirect_back_or_to assignments_admin_confirmations_path, alert: e.message
    end

    def auto_assign
      return head(:forbidden) if agent_view?

      result = Confirmations::Assignments.new(store: current_store, user: current_user).auto_assign!(by: current_user)
      notice = t("call_assignments.auto_done", count: result[:assigned])
      notice += " #{t("call_assignments.auto_left", count: result[:left])}" if result[:left].positive?
      redirect_to assignments_admin_confirmations_path(agent: "all"), notice: notice
    rescue Confirmations::Assignments::Error => e
      redirect_to assignments_admin_confirmations_path, alert: e.message
    end

    # "Analyses": the call-center figures of the orders created in the range. An agent only sees her own calls;
    # the owner can look at one agent with ?agent_id=.
    def analytics
      @date_range = selected_date_range(scope: "call_analytics", default: "last_30")
      agent = agent_view? ? current_user : (current_store.users.find_by(id: params[:agent_id]) if params[:agent_id].present?)
      @analytics = Confirmations::Analytics.new(store: current_store, from: @date_range.from, to: @date_range.to, range: @date_range.time_range, agent: agent)
      # overview, agents (all of them side by side), agent (one of them, chosen from the list). An agent only has her own overview.
      @view =
        if agent_view? then "overview"
        elsif params[:view] == "agents" then "agents"
        elsif agent || params[:view] == "agent" then "agent"
        else "overview"
        end
      # The team median and the other agents are needed to compare one agent, to choose one, or to see them side by side.
      if %w[agents agent].include?(@view) || agent
        @comparison = Confirmations::AgentComparison.new(store: current_store, from: @date_range.from, to: @date_range.to, range: @date_range.time_range)
      end
    end

    def dashboard
      @period = period_param
      @performance = Confirmations::Performance.new(store: current_store, range: period_range(@period),
        only: (current_user if agent_view?))
      @rows = @performance.rows
      @totals = @performance.totals
      @open_shift = ConfirmationShift.open.find_by(store: current_store, user: current_user)
    end

    # Page-open presence for agents (main). Kept alongside stack clock_in / clock_out.
    def presence
      if agent_view?
        tracker = Confirmations::Presence.new(store: current_store, user: current_user)
        params[:away] == "1" ? tracker.leave! : tracker.ping!
      end
      head :no_content
    rescue Confirmations::Presence::Error
      head :no_content
    end

    # "Pointages": who was on shift and when. Owners and supervisors only.
    def attendance
      return head(:forbidden) if agent_view?

      @date_range = selected_date_range(scope: "attendance", default: "last_7")
      @attendance = Confirmations::Attendance.new(store: current_store, range: @date_range.time_range, agent_id: params[:agent_id])
    end

    # Sent by the page every 30 seconds while an agent is on shift and the page is visible. The answer says whether the shift is still open.
    def heartbeat
      open = Confirmations::Shifts.new(store: current_store, user: current_user).heartbeat
      render json: { open: open }
    rescue Confirmations::Shifts::Error
      render json: { open: false }
    end

    def clock_in
      Confirmations::Shifts.new(store: current_store, user: current_user).clock_in
      back_to_where_it_was notice: t("admin.confirmations.clocked_in")
    rescue Confirmations::Shifts::Error => e
      back_to_where_it_was alert: e.message
    end

    def clock_out
      Confirmations::Shifts.new(store: current_store, user: current_user).clock_out
      back_to_where_it_was notice: t("admin.confirmations.clocked_out")
    rescue Confirmations::Shifts::Error => e
      back_to_where_it_was alert: e.message
    end

    # Clocking in or out keeps the person on the page they clicked from (call center, dashboard...): the button works in place.
    def back_to_where_it_was(flash)
      redirect_back_or_to dashboard_admin_confirmations_path(period: period_param), **flash
    end
    private :back_to_where_it_was

    def claim
      desk.claim(params[:order_id])
      redirect_to admin_confirmations_path(filter: "mine"), notice: t("admin.confirmations.claimed")
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid => e
      redirect_to admin_confirmations_path, alert: e.message
    end

    # Call panel endpoints (JSON, used by the panel's Stimulus controller).
    def call
      confirmation = desk.open_call(params[:order_id])
      render json: { order_id: confirmation.order_id, call_started_at: confirmation.call_started_at.iso8601(3), server_now: Time.current.iso8601(3) }
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    # The call window: opened from "Appeler" in the order-modal frame. It shows the customer, the products and the result buttons;
    # the call itself (claim, clock, finish) goes through the JSON endpoints below.
    def panel
      @order = current_store.orders.includes(order_items: [ :product, :product_variant ]).find(params[:order_id])
      return redirect_to(center_admin_confirmations_path, alert: t("call_panel.not_callable")) unless @order.status == "new" && @order.archived_at.nil? && @order.sendit_code.blank?

      product_ids = @order.order_items.filter_map(&:product_id)
      @variants = ProductVariant.where(product_id: product_ids, active: true).order(:id).group_by(&:product_id)
      render :panel, layout: (turbo_frame_request? ? false : "admin")
    end

    def abandon_call
      desk.abandon_call(params[:order_id])
      render json: { ok: true }
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def finish_call
      desk.finish_call(params[:order_id], outcome: params[:outcome], notes: params[:notes], callback_at: params[:callback_at], changes: call_changes)
      render json: { ok: true, next_order_id: next_available_order_id(excluding: params[:order_id]) }
    rescue Confirmations::Desk::Error, ActiveRecord::RecordInvalid, ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def touch_call
      desk.touch_call(params[:order_id])
      render json: { ok: true }
    rescue Confirmations::Desk::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    # Logs "who opened WhatsApp, when", then opens WhatsApp with the ready message.
    def whatsapp
      order = desk.log_whatsapp(params[:order_id])
      message = t("admin.confirmations.whatsapp_message", name: order.customer_name, store: current_store.name, number: order.number, total: order.total_display)
      redirect_to "https://wa.me/#{order.customer_phone.to_s.gsub(/\D/, "")}?text=#{ERB::Util.url_encode(message)}", allow_other_host: true
    rescue Confirmations::Desk::Error => e
      redirect_back_or_to admin_confirmations_path, alert: e.message
    end

    def block_number
      desk.block_number(params[:order_id], reason: params[:reason])
      redirect_back_or_to admin_confirmations_path, notice: t("admin.confirmations.number_blocked")
    rescue Confirmations::Desk::Error => e
      redirect_back_or_to admin_confirmations_path, alert: e.message
    end

    def unblock
      desk.unblock(params[:order_id])
      redirect_back_or_to admin_orders_path, notice: t("admin.confirmations.number_unblocked")
    rescue Confirmations::Desk::Error => e
      redirect_back_or_to admin_orders_path, alert: e.message
    end

    def force_release
      desk.force_release(params[:order_id])
      redirect_back_or_to admin_confirmations_path, notice: t("admin.confirmations.released")
    rescue Confirmations::Desk::Error => e
      redirect_back_or_to admin_confirmations_path, alert: e.message
    end

    def requeue
      desk.requeue(params[:order_id], phone: params[:phone])
      redirect_back_or_to admin_orders_path, notice: t("admin.confirmations.requeued")
    rescue Confirmations::Desk::Error => e
      redirect_back_or_to admin_orders_path, alert: e.message
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

    # The edits sent by the panel, in the order editor's shape; nil when the panel sent none.
    def call_changes
      return unless params[:order].present?

      raw = params.require(:order).permit(:name, :phone, :second_phone, :city, :district, :address, lines: [ :product_id, :product_variant_id, :quantity ])
      lines = raw[:lines]
      lines = lines.values if lines.respond_to?(:values) && !lines.is_a?(Array)
      attrs = raw.to_h.symbolize_keys
      attrs[:lines] = Array(lines) if raw.key?(:lines)
      attrs
    end

    # Oldest order waiting for a first call (unassigned, due, not a wrong number), skipping the one just handled.
    def next_available_order_id(excluding:)
      current_store.orders.active.where(status: "new", sendit_code: [ nil, "" ]).where.not(id: excluding)
        .joins("LEFT JOIN order_confirmations ON order_confirmations.order_id = orders.id")
        .where("order_confirmations.assigned_user_id IS NULL")
        .where(agent_queue_condition, current_user.id)
        .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition NOT IN ('wrong_number', 'blocked')")
        .where("order_confirmations.callback_at IS NULL OR order_confirmations.callback_at <= ?", Time.current)
        .order(Arel.sql("order_confirmations.callback_at ASC NULLS LAST, orders.created_at ASC, orders.id ASC")).pick("orders.id")
    end

    # Which waiting orders an agent may take: with an active attribution rule only the ones given to them, otherwise the open pool too.
    def agent_queue_condition
      if current_store.assignment_enforced?
        "order_confirmations.attributed_user_id = ?"
      else
        "order_confirmations.attributed_user_id IS NULL OR order_confirmations.attributed_user_id = ?"
      end
    end

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

    # The order the agent should handle next: an open call, then a claim, then the oldest order waiting.
    def agent_focus
      scope = current_store.orders.active.where(status: "new", sendit_code: [ nil, "" ]).includes(:order_items)
        .joins("LEFT JOIN order_confirmations ON order_confirmations.order_id = orders.id")
      held = scope.where(order_confirmations: { assigned_user_id: current_user.id })
        .order(Arel.sql("(order_confirmations.call_started_at IS NULL), order_confirmations.claimed_at ASC")).first
      return held if held

      available = scope.where("order_confirmations.assigned_user_id IS NULL")
        .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition NOT IN ('wrong_number', 'blocked')")
        .where("order_confirmations.callback_at IS NULL OR order_confirmations.callback_at <= ?", Time.current)
      available = available.where(agent_queue_condition, current_user.id)
      available.order(Arel.sql("(orders.import_contact_issues = '[]'::jsonb) DESC, order_confirmations.callback_at ASC NULLS LAST, orders.created_at ASC, orders.id ASC")).first
    end

    def assignment_params
      params.permit(:agent, :status, :missed, :source, :product, :q, :sort, :per, :page).to_h.symbolize_keys
    end
  end
end
