module Admin
  # "Facturation" of a confirmation agent: their own earnings, payouts and return deductions. Every query is scoped to
  # the signed-in user and their store, so an agent never sees what another agent earns.
  class MyBillingController < BaseController
    include DateRangeSelection

    before_action :require_store_context!

    # The date picker moves the period earnings, the payout history and the deductions; the cumulated earnings, what was paid and what is left are
    # always the whole history, so they never change with the period.
    def show
      @date_range = selected_date_range(scope: "my_billing", default: "this_month")
      range = @date_range.time_range
      @summary = Team::AgentEarnings.new(store: current_store, range: range).summary_for(current_user)
      @payments = AgentPayment.where(store: current_store, user: current_user, paid_at: range).includes(proof_attachment: :blob).order(paid_at: :desc).limit(50)
      @deductions = AgentDeduction.where(store: current_store, user: current_user, created_at: range).includes(:order).order(created_at: :desc).limit(50)
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end
  end
end
