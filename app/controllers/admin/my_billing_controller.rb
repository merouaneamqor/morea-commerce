module Admin
  # "Facturation" of a confirmation agent: their own earnings, payouts and return deductions. Every query is scoped to
  # the signed-in user and their store, so an agent never sees what another agent earns.
  class MyBillingController < BaseController
    before_action :require_store_context!

    def show
      month = Time.current.beginning_of_month..Time.current
      @summary = Team::AgentEarnings.new(store: current_store, range: month).summary_for(current_user)
      @payments = AgentPayment.where(store: current_store, user: current_user).order(paid_at: :desc).limit(50)
      @deductions = AgentDeduction.where(store: current_store, user: current_user).includes(:order).order(created_at: :desc).limit(50)
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end
  end
end
