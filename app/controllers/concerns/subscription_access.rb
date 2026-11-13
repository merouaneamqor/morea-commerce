# frozen_string_literal: true

# Shared predicate for authenticated merchant entry points. APIs must apply this
# after authenticating their store token and return their native error response.
module SubscriptionAccess
  extend ActiveSupport::Concern

  included do
    helper_method :subscription_access?
  end

  private

  def subscription_access?
    super_admin? || current_store&.operational_access? || false
  end

  def require_subscription_access!
    return if subscription_access? || subscription_public_admin_page?

    if request.format.html? || request.format.turbo_stream?
      redirect_to admin_subscription_path, alert: t("subscriptions.required"), status: :see_other
    else
      render json: { error: "subscription_required", message: t("subscriptions.required") }, status: :payment_required
    end
  end

  def subscription_public_admin_page?
    return false unless request.get? || request.head?

    (controller_path == "admin/dashboard" && action_name == "show") ||
      (controller_path == "admin/subscriptions" && action_name == "show")
  end
end
