module Admin
  # "Facturation" of the call center, for the owner: what every agent earned, was paid and is owed, and the payout with how it was made (cash or
  # bank transfer), a reference and the proof. Every query is scoped to the store. Agents have their own page (MyBillingController).
  class AgentBillingController < BaseController
    include DateRangeSelection

    before_action :require_store_context!
    before_action :require_payer!

    def show
      @date_range = selected_date_range(scope: "agent_billing", default: "this_month")
      range = @date_range.time_range
      earnings = Team::AgentEarnings.new(store: current_store, range: range)
      @agents = current_store.users.active.where(confirmation_role: "agent").order(:name, :email).to_a
      @rows = @agents.map do |agent|
        { agent: agent, summary: earnings.summary_for(agent), payout: Team::AgentPayout.new(store: current_store, agent: agent, paid_by: current_user).preview,
          paid_in_range: AgentPayment.where(store: current_store, user: agent, paid_at: range).sum(:amount_cents) }
      end
      @payments = AgentPayment.where(store: current_store, paid_at: range).includes(:user, :paid_by, proof_attachment: :blob).order(paid_at: :desc).limit(100)
    end

    def pay
      agent = current_store.users.where(confirmation_role: "agent").find(params[:user_id])
      payment = Team::AgentPayout.new(store: current_store, agent: agent, paid_by: current_user)
        .pay!(method: params[:payment_method], reference: params[:reference], proof: params[:proof])
      redirect_to admin_agent_billing_path, notice: t("admin.team.paid", name: payment.user.name.presence || payment.user.email)
    rescue Team::AgentPayout::Error => e
      redirect_to admin_agent_billing_path, alert: e.message == "Nothing to pay." ? t("admin.team.nothing_to_pay") : e.message
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    # Only the owner (or the platform) pays; agents and supervisors do not.
    def require_payer!
      head :forbidden unless current_user&.super_admin? || current_user&.admin?
    end
  end
end
