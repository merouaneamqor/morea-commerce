module Admin
  class BaseController < ApplicationController
    include SubscriptionAccess

    layout "admin"
    before_action :require_admin!
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
      return if current_user&.super_admin? || current_user&.admin?

      redirect_to admin_login_path, alert: "Please sign in."
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
  end
end
