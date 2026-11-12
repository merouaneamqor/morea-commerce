module Confirmations
  # Everything the call center page prints: the figures of the cards, the counters of the tabs and the list,
  # from one set of scopes so the numbers cannot disagree. Printing only; no figure is computed in the view.
  #
  # An agent sees her own orders and the unassigned ones, a manager sees the whole store.
  # - Queue tabs (En attente, Injoignables, Planifiée, Bloqués) are the live queue: they ignore the date range.
  #   Injoignables are the new orders whose last call got no answer (they are also still in En attente until the third try cancels them).
  # - The other tabs are the orders confirmed (or cancelled) in the date range: the confirmation time for
  #   confirmed orders, the cancelling call (or, for managers, the cancelling time) for cancelled ones. For an
  #   agent only the orders she confirmed or cancelled herself.
  class CallCenter
    TABS = %w[pending unreachable rescheduled failed planned confirmed delivered returns cancelled paid blocked].freeze
    CONFIRMED_STATUSES = %w[confirmed preparing awaiting_pickup picked_up in_transit out_for_delivery].freeze
    FAILED_STATUSES = %w[unreachable address_issue].freeze
    PER_PAGE = 25

    Figures = Data.define(:assigned, :pending, :failed, :confirmed, :delivered, :cancelled, :returned)

    def initialize(store:, user:, range:, params: {})
      @store, @user, @range, @params = store, user, range, params
    end

    def agent? = @user.confirmation_agent_view?

    def tab
      TABS.include?(@params[:tab]) ? @params[:tab] : "pending"
    end

    def figures
      @figures ||= Figures.new(
        assigned: assigned_count,
        pending: tab_scope("pending").count,
        failed: tab_scope("failed").count,
        confirmed: confirmed_in_range.count,
        delivered: tab_scope("delivered").count,
        cancelled: tab_scope("cancelled").count,
        returned: tab_scope("returns").count
      )
    end

    def counts
      @counts ||= TABS.index_with { |key| tab_scope(key).count }
    end

    def failed_count = counts["failed"]

    # The page of orders for the current tab and filters.
    def orders
      @orders ||= filtered(tab_scope(tab)).preload(:order_items, :customer, :order_confirmation, external_order_receipt: :store_connection)
        .order(order_clause).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    end

    def page = [ @params[:page].to_i, 1 ].max
    def next_page? = orders.length > PER_PAGE
    def rows = orders.first(PER_PAGE)

    def attempt_counts
      @attempt_counts ||= ConfirmationAttempt.joins(:order_confirmation).where(store: @store, order_confirmations: { order_id: rows.map(&:id) })
        .group("order_confirmations.order_id").count
    end

    # order id => the call that cancelled it (the agent, the reason typed, the time); the latest one wins. Used by the Annulée tab.
    def cancellations
      @cancellations ||= ConfirmationAttempt.joins(:order_confirmation).where(store: @store, outcome: "cancelled", order_confirmations: { order_id: rows.map(&:id) })
        .includes(:user, :order_confirmation).order(:created_at).each_with_object({}) { |attempt, by_order| by_order[attempt.order_confirmation.order_id] = attempt }
    end

    # order id => the latest "WhatsApp opened" event
    def whatsapp_events
      @whatsapp_events ||= OrderEvent.where(order_id: rows.map(&:id), kind: "whatsapp").includes(:user).order(:created_at).each_with_object({}) { |event, by_order| by_order[event.order_id] = event }
    end

    def products
      @store.products.visible.order(:name).pluck(:name, :id)
    end

    def sources
      @store.store_connections.order(:name).pluck(:name, :id)
    end

    private

    def base
      scope = @store.orders.active
      return scope unless agent?

      held_by_others = OrderConfirmation.where(store: @store).where.not(assigned_user_id: [ nil, @user.id ]).select(:order_id)
      scope.where.not(id: held_by_others)
    end

    def with_confirmation = base.joins("LEFT JOIN order_confirmations ON order_confirmations.order_id = orders.id")

    # Orders confirmed by this agent (any agent for a manager).
    def confirmed_by_scope(scope)
      return scope unless agent?

      scope.where(id: ConfirmationAttempt.joins(:order_confirmation).where(store: @store, user: @user, outcome: "confirmed").select("order_confirmations.order_id"))
    end

    def confirmed_in_range
      confirmed_by_scope(base).where(confirmed_at: @range)
    end

    def tab_scope(key)
      case key
      when "pending"
        with_confirmation.where(status: "new", sendit_code: [ nil, "" ])
          .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition IN ('pending', 'no_answer')")
          .where("order_confirmations.callback_at IS NULL OR order_confirmations.callback_at <= ?", Time.current)
      when "unreachable"
        with_confirmation.where(status: "new", sendit_code: [ nil, "" ]).where(order_confirmations: { disposition: "no_answer" })
      when "planned"
        with_confirmation.where(status: "new").where(order_confirmations: { disposition: "callback" })
      when "blocked"
        with_confirmation.where(status: "new").where(order_confirmations: { disposition: "blocked" })
      when "rescheduled" then confirmed_in_range.where(status: "postponed")
      when "failed" then confirmed_in_range.where(status: FAILED_STATUSES)
      when "confirmed" then confirmed_in_range.where(status: CONFIRMED_STATUSES)
      when "delivered" then confirmed_in_range.where(status: "delivered")
      when "returns" then confirmed_in_range.where(status: "returned")
      when "paid" then confirmed_in_range.where(status: "delivered").where.not(collected_at: nil)
      when "cancelled" then cancelled_in_range
      end
    end

    def cancelled_in_range
      if agent?
        base.where(status: "cancelled", id: ConfirmationAttempt.joins(:order_confirmation).where(store: @store, user: @user, outcome: "cancelled", created_at: @range).select("order_confirmations.order_id"))
      else
        base.where(status: "cancelled", cancelled_at: @range)
      end
    end

    # Orders she holds right now or has a recorded call on in the range (a manager: orders with a call in the range).
    def assigned_count
      called = ConfirmationAttempt.joins(:order_confirmation).where(store: @store, created_at: @range)
      called = called.where(user: @user) if agent?
      ids = called.distinct.pluck("order_confirmations.order_id")
      ids |= OrderConfirmation.where(store: @store, assigned_user: @user).pluck(:order_id) if agent?
      base.where(id: ids).count
    end

    def filtered(scope)
      scope = scope.where(id: OrderItem.where(product_id: @params[:product]).select(:order_id)) if @params[:product].present?
      scope = filter_source(scope) if @params[:source].present?
      scope = filter_whatsapp(scope) if %w[sent not_sent].include?(@params[:whatsapp])
      if @params[:missed] == "1"
        scope = scope.where(id: ConfirmationAttempt.joins(:order_confirmation).where(store: @store, outcome: "no_answer").select("order_confirmations.order_id"))
      end
      if @params[:q].present?
        like = "%#{Order.sanitize_sql_like(@params[:q].to_s.strip)}%"
        scope = scope.where("orders.number ILIKE :q OR orders.customer_name ILIKE :q OR orders.customer_phone ILIKE :q", q: like)
      end
      scope
    end

    def filter_source(scope)
      return scope.where.not(id: ExternalOrderReceipt.select(:order_id)) if @params[:source] == "manual"

      scope.where(id: ExternalOrderReceipt.where(store_connection_id: @store.store_connections.where(id: @params[:source]).select(:id)).select(:order_id))
    end

    def filter_whatsapp(scope)
      sent = OrderEvent.where(kind: "whatsapp").select(:order_id)
      @params[:whatsapp] == "sent" ? scope.where(id: sent) : scope.where.not(id: sent)
    end

    def order_clause
      @params[:sort] == "oldest" ? { created_at: :asc, id: :asc } : { created_at: :desc, id: :desc }
    end
  end
end
