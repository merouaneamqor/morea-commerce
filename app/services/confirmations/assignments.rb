module Confirmations
  # The "Attributions" page: who the orders waiting for a call are for. An owner or a supervisor attributes an order to an agent by hand, or
  # lets the automatic attribution spread the unattributed ones over the agents who are on shift. An attributed order is only offered to that
  # agent (the other agents' queues hide it, and they cannot claim it); an unattributed one stays open to everybody.
  #
  # - An agent is a user with the confirmation role "agent". "Actif" = she has a shift open (she clocked in).
  # - The load of an agent is the number of waiting orders attributed to her; CAPACITY is what the automatic attribution fills her up to.
  # - Reussite = confirmed calls over all her calls of the last 30 days (abandoned ones excluded); nil when she made none.
  class Assignments
    class Error < StandardError; end

    CAPACITY = 20
    PER_PAGE_OPTIONS = [ 10, 25, 50 ].freeze
    STATUS_FILTERS = %w[pending no_answer callback].freeze
    SUCCESS_WINDOW = 30.days

    def initialize(store:, user: nil, params: {})
      @store, @user, @params = store, user, params
    end

    # --- people -----------------------------------------------------------------------------------------------------
    def agents
      @agents ||= @store.users.active.where(confirmation_role: "agent").order(:name, :id).to_a
    end

    def on_shift?(agent) = on_shift_ids.include?(agent.id)

    # One card per agent: waiting orders attributed to her, calls made today, success rate, load against capacity.
    def agent_cards
      @agent_cards ||= agents.map do |agent|
        pending = loads[agent.id].to_i
        { user: agent, on_shift: on_shift?(agent), pending: pending, today: calls_today[agent.id].to_i, success: success_rates[agent.id], capacity: CAPACITY,
          load_percent: (pending * 100.0 / CAPACITY).round }
      end
    end

    def unattributed_count = @unattributed_count ||= waiting_scope.where("order_confirmations.attributed_user_id IS NULL").count

    # { agent id => waiting orders attributed to her }
    def loads
      @loads ||= waiting_scope.where.not(order_confirmations: { attributed_user_id: nil }).group("order_confirmations.attributed_user_id").count
    end

    # --- the list ---------------------------------------------------------------------------------------------------
    def agent_filter
      value = @params[:agent].to_s
      return value if %w[all none].include?(value) || agents.any? { |agent| agent.id.to_s == value }

      "none"
    end

    def status_filter = STATUS_FILTERS.include?(@params[:status].to_s) ? @params[:status].to_s : nil
    def per_page = PER_PAGE_OPTIONS.include?(@params[:per].to_i) ? @params[:per].to_i : PER_PAGE_OPTIONS.second
    def page = [ @params[:page].to_i, 1 ].max
    def oldest_first? = @params[:sort].to_s == "oldest"
    def filtered? = %i[q status missed source product].any? { |key| @params[key].present? } || agent_filter != "none"

    def orders
      @orders ||= filtered(waiting_scope).preload(:order_items, :customer, :order_confirmation, external_order_receipt: :store_connection)
        .order(oldest_first? ? { created_at: :asc, id: :asc } : { created_at: :desc, id: :desc }).offset((page - 1) * per_page).limit(per_page + 1).to_a
    end

    def rows = orders.first(per_page)
    def next_page? = orders.length > per_page
    def total = @total ||= filtered(waiting_scope).count

    def missed_counts
      @missed_counts ||= ConfirmationAttempt.joins(:order_confirmation).where(store: @store, outcome: "no_answer", order_confirmations: { order_id: rows.map(&:id) })
        .group("order_confirmations.order_id").count
    end

    def products = @store.products.visible.order(:name).pluck(:name, :id)
    def sources = @store.store_connections.order(:name).pluck(:name, :id)

    # --- doing it ---------------------------------------------------------------------------------------------------
    # Attributes one order to an agent, or takes the attribution away (blank agent). A claim held by somebody else is released.
    def assign!(order_id, agent_id, by:)
      agent = nil
      if agent_id.present?
        agent = agents.find { |candidate| candidate.id == agent_id.to_i }
        raise Error, "Choose an agent of this store." unless agent
      end
      Order.transaction do
        # The row is locked on the orders table alone (a lock cannot be taken through the outer join of the waiting scope), then checked again.
        order = @store.orders.lock.find_by(id: order_id)
        raise Error, "This order is no longer waiting for a call." unless order && waiting_scope.where(id: order.id).exists?

        attribute!(order, agent, by: by, how: "by")
      end
      agent
    end

    # Spreads the unattributed orders over the agents on shift, oldest first, always to the least loaded one, and stops when everybody is at
    # capacity. Returns { assigned:, left:, per_agent: { agent => count } }.
    def auto_assign!(by:)
      active = agents.select { |agent| on_shift?(agent) }
      raise Error, "No agent is on shift: nobody to attribute the orders to." if active.empty?

      load = active.to_h { |agent| [ agent, loads[agent.id].to_i ] }
      per_agent = Hash.new(0)
      Order.transaction do
        ids = waiting_scope.where("order_confirmations.attributed_user_id IS NULL").order(:created_at, :id).pluck("orders.id")
        ids.each do |order_id|
          agent, count = load.min_by { |candidate, current| [ current, candidate.id ] }
          break if count >= CAPACITY

          order = @store.orders.lock.find(order_id)
          attribute!(order, agent, by: by, how: "automatically by")
          load[agent] += 1
          per_agent[agent] += 1
        end
      end
      reset!
      { assigned: per_agent.values.sum, left: unattributed_count, per_agent: per_agent }
    end

    # The orders waiting for a call (also used by AssignmentRunner).
    def waiting_scope
      @waiting_scope ||= @store.orders.active.where(status: "new", sendit_code: [ nil, "" ])
        .joins("LEFT JOIN order_confirmations ON order_confirmations.order_id = orders.id")
        .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition NOT IN ('wrong_number', 'blocked')")
    end

    private

    def attribute!(order, agent, by:, how:)
      confirmation = OrderConfirmation.find_or_create_by!(order: order) { |row| row.store = @store }
      attrs = { attributed_user: agent, attributed_at: (Time.current if agent), assignment_rule: nil }
      attrs.merge!(assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil) if confirmation.assigned_user_id && confirmation.assigned_user_id != agent&.id
      confirmation.update!(attrs)
      who = by.name.presence || by.email
      order.record_event!("comment", body: agent ? "Assigned to #{agent.name.presence || agent.email} #{how} #{who}" : "Assignment removed by #{who}", user: by)
    end

    def reset!
      @loads = @unattributed_count = @agent_cards = @orders = @total = @waiting_scope = nil
    end

    def on_shift_ids = @on_shift_ids ||= ConfirmationShift.open.where(store: @store).pluck(:user_id)

    def calls_today
      @calls_today ||= ConfirmationAttempt.where(store: @store, created_at: Time.current.in_time_zone(DateRange::ZONE).beginning_of_day..).where.not(outcome: "abandoned").group(:user_id).count
    end

    def success_rates
      @success_rates ||= begin
        calls = ConfirmationAttempt.where(store: @store, created_at: SUCCESS_WINDOW.ago..).where.not(outcome: "abandoned").group(:user_id, :outcome).count
        calls.keys.map(&:first).uniq.to_h do |user_id|
          made = calls.sum { |(id, _), count| id == user_id ? count : 0 }
          [ user_id, (calls[[ user_id, "confirmed" ]].to_i * 100.0 / made).round(1) ]
        end
      end
    end

    def filtered(scope)
      case agent_filter
      when "none" then scope = scope.where("order_confirmations.attributed_user_id IS NULL")
      when "all" then nil
      else scope = scope.where(order_confirmations: { attributed_user_id: agent_filter.to_i })
      end
      scope = status_scope(scope)
      scope = scope.where(id: ConfirmationAttempt.joins(:order_confirmation).where(store: @store, outcome: "no_answer").select("order_confirmations.order_id")) if @params[:missed] == "1"
      scope = scope.where(id: OrderItem.where(product_id: @params[:product]).select(:order_id)) if @params[:product].present?
      scope = filter_source(scope) if @params[:source].present?
      if @params[:q].present?
        like = "%#{Order.sanitize_sql_like(@params[:q].to_s.strip)}%"
        scope = scope.where("orders.number ILIKE :q OR orders.customer_name ILIKE :q OR orders.customer_phone ILIKE :q", q: like)
      end
      scope
    end

    def status_scope(scope)
      case status_filter
      when "pending" then scope.where("order_confirmations.disposition IS NULL OR order_confirmations.disposition = 'pending'")
      when "no_answer" then scope.where(order_confirmations: { disposition: "no_answer" })
      when "callback" then scope.where(order_confirmations: { disposition: "callback" })
      else scope
      end
    end

    def filter_source(scope)
      return scope.where.not(id: ExternalOrderReceipt.select(:order_id)) if @params[:source] == "manual"

      scope.where(id: ExternalOrderReceipt.where(store_connection_id: @store.store_connections.where(id: @params[:source]).select(:id)).select(:order_id))
    end
  end
end
