# frozen_string_literal: true

# Steps 2 and 3 of the seallo signup: choose a plan (with or without an account yet), then pay.
class SubscriptionSetupController < ApplicationController
  layout "signup_flow"
  before_action :require_apex!
  before_action :require_owner!, only: %i[payment transfer]
  before_action :require_plan_workspace!, only: %i[payment transfer]

  # Step 2: show the plans.
  def plans
    store = plan_owner&.store
    chosen = session[:signup_plan] || {}
    @guest = plan_owner.nil?
    @current = store&.plan_selected? ? store.plan : chosen["plan"]
    @current_billing = store&.plan_selected? ? store.billing_interval.sub("yearly", "annual") : chosen["billing"]
    @current_currency = store&.plan_selected? ? store.currency : chosen["currency"]
  end

  # Step 2: save the chosen plan and start the trial, then go on to payment.
  def choose
    plan = params[:plan].to_s
    billing = params[:billing].to_s
    currency = params[:currency].presence || Plans.reference_currency
    unless Plans.plan?(plan) && Plans::BILLINGS.include?(billing) && Plans.currency?(currency)
      return redirect_to plans_path(locale: I18n.locale), alert: t("signup_plans.invalid"), status: :see_other
    end

    owner = plan_owner
    # No account yet: remember the choice and move on to creating the account.
    unless owner
      session[:signup_plan] = { "plan" => plan, "billing" => billing, "currency" => currency }
      return redirect_to signup_path(locale: I18n.locale), status: :see_other
    end
    # Workspaces that predate plans keep their existing billing policy.
    return redirect_to admin_root_path, status: :see_other unless owner.store.plan_selected?

    owner.store.choose_plan!(plan: plan, billing: billing, currency: currency)
    return redirect_to admin_root_path, notice: t("signup_plans.changed"), status: :see_other if owner.store.free_plan?

    # A signed-in owner changes plan with one click: no payment step for now, the plan is active as if paid.
    if Plans.skip_payment?
      owner.store.activate_plan_without_payment!
      return redirect_to admin_root_path, notice: t("signup_plans.changed"), status: :see_other
    end

    redirect_to payment_path(locale: I18n.locale), status: :see_other
  end

  # Step 3: summary and payment methods.
  def payment
    @store = plan_owner.store
    return redirect_to plans_path(locale: I18n.locale) unless @store.trial_ends_at
    return redirect_to admin_root_path if @store.free_plan?

    @pending = @store.payments.pending.where(payment_method: "transfer").order(created_at: :desc).first
    @bank = Plans.bank
  end

  # Step 3: the seller declares a bank transfer, which seallo verifies afterwards.
  def transfer
    store = plan_owner.store
    reference = params[:reference].to_s.strip
    return redirect_to payment_path(locale: I18n.locale), alert: t("signup_payment.reference_required"), status: :see_other if reference.blank?
    return redirect_to payment_path(locale: I18n.locale), alert: t("signup_payment.reference_too_long"), status: :see_other if reference.length > 100

    store.with_lock do
      # One transfer waiting for verification at a time: update it when it exists.
      payment = store.payments.pending.find_or_initialize_by(payment_method: "transfer")
      payment.update!(plan: store.plan, billing: store.billing_interval.sub("yearly", "annual"), amount: store.amount_due, currency: Plans.reference_currency, reference: reference)
    end
    redirect_to payment_path(locale: I18n.locale), notice: t("signup_payment.declared"), status: :see_other
  end

  private

  def require_apex!
    render template: "stores/missing", layout: "bare", status: :not_found unless Store.apex_host?(request.host)
  end

  def plan_owner
    return @plan_owner if defined?(@plan_owner)

    user = User.active.find_by(id: session[:user_id]) if session[:user_id]
    valid = user && session[:session_version].to_i == user.session_version && user.store && user.admin? && !user.super_admin?
    @plan_owner = valid ? user : nil
  end

  def require_owner!
    redirect_to admin_login_path(locale: I18n.locale) unless plan_owner
  end

  def require_plan_workspace!
    redirect_to admin_root_path unless plan_owner&.store&.plan_selected?
  end
end
