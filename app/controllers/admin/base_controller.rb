module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin!

    helper_method :current_user

    private

    def current_user
      return @current_user if defined?(@current_user)

      @current_user = current_store&.users&.find_by(id: session[:user_id]) if session[:user_id]
    end

    def require_admin!
      return if current_user&.admin?

      redirect_to admin_login_path, alert: "Please sign in."
    end
  end
end
