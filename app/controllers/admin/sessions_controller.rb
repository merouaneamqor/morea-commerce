module Admin
  class SessionsController < ApplicationController
    layout "auth"

    def new
      redirect_to after_login_path if current_admin_user
    end

    def create
      email = params[:email].to_s.strip.downcase
      user = current_store&.users&.find_by(email: email) || User.super_admins.find_by(email: email)

      if user&.authenticate(params[:password])
        session[:user_id] = user.id
        session[:admin_mode] = user.super_admin? ? "platform" : "store"
        redirect_to after_login_path_for(user), notice: "Welcome back."
      else
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:user_id)
      session.delete(:admin_mode)
      redirect_to admin_login_path, notice: "Signed out."
    end

    private

    def after_login_path
      after_login_path_for(current_admin_user)
    end

    def after_login_path_for(user)
      return_to = session.delete(:return_to).to_s
      return return_to if return_to.start_with?("/") && !return_to.start_with?("//")

      user&.super_admin? ? admin_platform_path : admin_root_path
    end
  end
end
