module Team
  # Order outcomes and pay for the agents of one store. An order counts for the agent
  # holding its confirmation claim once the call was confirmed; pay accrues per
  # delivered order at the agent's rate. Every query is scoped to the store.
  class AgentEarnings
    # Delivery states reported on "Mes statistiques" (courier-owned, so shown as-is).
    PICKUP = %w[awaiting_pickup].freeze
    IN_DELIVERY = %w[picked_up in_transit out_for_delivery].freeze
    POSTPONED = %w[postponed].freeze
    UNREACHABLE = %w[unreachable address_issue].freeze

    Figures = Data.define(:confirmed, :cancelled, :pickup, :in_delivery, :delivered, :postponed, :unreachable, :returned) do
      def delivery_rate = confirmed.zero? ? nil : delivered.fdiv(confirmed)
    end

    Summary = Data.define(:user, :figures, :earned_period, :earned_total, :paid_total, :last_paid_at, :pending_deductions, :applied_deductions) do
      def unpaid = [ earned_total - paid_total, 0 ].max
      # Cash actually handed over: settled earnings minus the deductions those payouts subtracted.
      def cash_paid = paid_total - applied_deductions
    end

    def initialize(store:, range:)
      @store, @range = store, range
    end

    def summary_for(user)
      rate = user.pay_per_delivery_cents
      Summary.new(
        user: user,
        figures: figures_for(user),
        earned_period: delivered_ids(user, @range).size * rate,
        earned_total: delivered_ids(user, nil).size * rate,
        paid_total: payments(user).sum(:amount_cents),
        last_paid_at: payments(user).maximum(:paid_at),
        pending_deductions: AgentDeduction.pending.where(store: @store, user: user).sum(:amount_cents),
        applied_deductions: payments(user).sum(:deductions_cents)
      )
    end

    # The delivered orders this agent is credited for, oldest delivery first (what a payout can settle).
    def delivered_orders(user)
      claims(user).where(status: "delivered").where.not(delivered_at: nil).order(:delivered_at, :id)
    end

    # Confirmed orders per day inside the range, for the bar chart.
    def confirmed_by_day(user)
      confirmed_orders(user, @range, by: :confirmed_at).group_by { |o| o.confirmed_at.in_time_zone(DateRange::ZONE).to_date }.transform_values(&:size)
    end

    private

    def figures_for(user)
      confirmed = confirmed_orders(user, @range, by: :confirmed_at).to_a
      statuses = confirmed.map(&:status).tally
      Figures.new(
        confirmed: confirmed.size,
        cancelled: cancelled_count(user),
        pickup: sum_of(statuses, PICKUP),
        in_delivery: sum_of(statuses, IN_DELIVERY),
        delivered: sum_of(statuses, %w[delivered]),
        postponed: sum_of(statuses, POSTPONED),
        unreachable: sum_of(statuses, UNREACHABLE),
        returned: sum_of(statuses, %w[returned])
      )
    end

    def sum_of(tally, keys) = keys.sum { |key| tally.fetch(key, 0) }

    def cancelled_count(user)
      ConfirmationAttempt.where(store: @store, user: user, outcome: "cancelled", created_at: @range).count
    end

    # Orders this agent holds or confirmed. Recording an outcome clears the claim, so the
    # audit attempt (outcome "confirmed" by this user) is what keeps the credit afterwards.
    def claims(user)
      confirmed_by_user = ConfirmationAttempt.joins(:order_confirmation)
        .where(store: @store, user: user, outcome: "confirmed").select("order_confirmations.order_id")
      Order.joins(:order_confirmation).where(store: @store)
        .where(order_confirmations: { assigned_user_id: user.id }).or(
          Order.joins(:order_confirmation).where(store: @store, id: confirmed_by_user)
        )
    end

    # Orders this agent confirmed. `by` picks the timestamp the range applies to.
    def confirmed_orders(user, range, by:)
      scope = claims(user).where(order_confirmations: { disposition: "confirmed" }).where.not(by => nil)
      range ? scope.where(by => range) : scope
    end

    def delivered_ids(user, range)
      scope = claims(user).where(status: "delivered").where.not(delivered_at: nil)
      scope = scope.where(delivered_at: range) if range
      scope.pluck(:id)
    end

    def payments(user)
      AgentPayment.where(store: @store, user: user)
    end
  end
end
