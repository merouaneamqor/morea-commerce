module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin!

    helper_method :current_user

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
  end
end
