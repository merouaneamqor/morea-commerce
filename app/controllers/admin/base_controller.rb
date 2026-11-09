module Admin
  class BaseController < ApplicationController
    include SubscriptionAccess
    include PersonalDataAccessLogging

    layout "admin"
    before_action :require_admin!
    before_action :confine_confirmation_agents!
    before_action :note_agent_on_platform
    before_action :sync_store_billing_past_due!
    before_action :require_subscription_access!

    helper_method :current_user, :store_billing_past_due?

private

# Merchant-entered MAD amount ("12", "12.5", "12,50") to integer cents; no silent rounding.
def parse_mad_cents(value)
  amount = BigDecimal(value.to_s.strip.tr(",", ".")) * 100
  raise ArgumentError, "Enter a valid amount with at most two decimals." unless amount.finite? && amount == amount.round

  amount.to_i
rescue ArgumentError
  raise ArgumentError, "Enter a valid amount with at most two decimals."
end

    def current_user
      current_admin_user
    end

    def require_admin!
      return if current_user&.super_admin? || current_user&.admin? || current_user&.confirmation_agent?

      redirect_to admin_login_path, alert: "Please sign in."
    end

    # Confirmation agents are not admins: they reach the desk, its performance page
    # and the billing page (needed when a subscription blocks the store).
    AGENT_ALLOWED_CONTROLLERS = %w[admin/confirmations admin/orders admin/my_stats admin/subscriptions admin/push_subscriptions].freeze

    def confine_confirmation_agents!
      return unless current_user&.confirmation_agent? && !current_user.super_admin?
      return if AGENT_ALLOWED_CONTROLLERS.include?(controller_path)

      redirect_to home_admin_confirmations_path
    end

    def require_super_admin!
      return if super_admin?

      redirect_to(current_user ? admin_root_path : admin_login_path, alert: "Super admin access required.")
    end

    def sync_store_billing_past_due!
      return unless current_store

      current_store.sync_billing_past_due!
    end

    def store_billing_past_due?
      current_store&.billing_past_due?
    end

    # A confirmation agent who has a platform page open can see orders. Closing
    # the page ends the session. The interval is a stat and is not used for pay.
    def note_agent_on_platform
      return unless current_user&.confirmation_agent_view? && current_store
      return if controller_path == "admin/confirmations" && action_name == "presence" && params[:away] == "1"

      Confirmations::Presence.new(store: current_store, user: current_user).ping!
      @agent_present = true
    rescue Confirmations::Presence::Error
      @agent_present = false
    end
  end
end
