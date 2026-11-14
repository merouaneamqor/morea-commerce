module Admin
  class BaseController < ApplicationController
    include SubscriptionAccess
    include PersonalDataAccessLogging

    layout "admin"
    before_action :require_admin!
    before_action :block_demo_writes!
    before_action :confine_confirmation_agents!
    before_action :enforce_area_permission!
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

    # The public demo workspace is read-only: any request that would change data is refused with a friendly message.
    def block_demo_writes!
      return unless Demo::Workspace.demo_store?(current_store)
      return if request.get? || request.head?
      # The bulk send answers itself in the demo (it only shows what would be sent).
      return if controller_path == "admin/orders" && action_name == "ship_confirmed"

      if request.format.html? || request.format.turbo_stream?
        redirect_back fallback_location: admin_root_path, alert: t("demo.read_only"), status: :see_other
      else
        render json: { error: "demo_read_only", message: t("demo.read_only") }, status: :forbidden
      end
    end

    def require_admin!
      return if current_user&.super_admin? || current_user&.admin? || current_user&.confirmation_agent?

      redirect_to admin_login_path, alert: "Please sign in."
    end

    # Confirmation agents are not admins: they reach the desk, its performance page
    # and the billing page (needed when a subscription blocks the store).
    AGENT_ALLOWED_CONTROLLERS = %w[admin/confirmations admin/orders admin/my_stats admin/my_billing admin/subscriptions admin/push_subscriptions].freeze

    def confine_confirmation_agents!
      return unless current_user&.confirmation_agent? && !current_user.super_admin?
      return if AGENT_ALLOWED_CONTROLLERS.include?(controller_path)

      redirect_to admin_my_stats_path
    end

    # The owner can close parts of the store to a person (custom_permissions): a page of a closed area sends them to one they can open, or says no.
    def enforce_area_permission!
      user = current_user
      # Only for someone whose owner chose a list: what their role gives stays handled by the pages themselves, as before.
      return unless user && !user.super_admin? && !user.custom_permissions.nil?

      area = Team::Roles.area_for(controller_path, action_name)
      return if area.nil? || user.area_allowed?(area)

      landing = permission_landing(user, area)
      if landing && request.format.html? && request.get?
        redirect_to landing, alert: t("admin.permissions.denied")
      else
        render plain: t("admin.permissions.denied"), status: :forbidden
      end
    end

    # The first page the person can open, other than the one that was refused.
    def permission_landing(user, denied_area)
      candidates = user.confirmation_agent_view? ? [ [ "dashboard", admin_my_stats_path ], [ "queue", center_admin_confirmations_path ], [ "own_billing", admin_my_billing_path ] ]
                                                 : [ [ "dashboard", admin_root_path ], [ "orders", admin_orders_path ], [ "queue", center_admin_confirmations_path ] ]
      candidates.find { |area, _path| area != denied_area && user.area_allowed?(area) }&.last
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
