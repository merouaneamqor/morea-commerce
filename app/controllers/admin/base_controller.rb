module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin!

    helper_method :current_user

    private

    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def require_admin!
      return if current_user&.admin?

      redirect_to admin_login_path, alert: "Please sign in."
    end
  end
end
