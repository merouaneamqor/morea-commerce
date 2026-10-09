module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin!
    before_action :sync_store_billing_past_due!

    helper_method :current_user, :store_billing_past_due?

    private

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
