module Admin
  class SessionsController < ApplicationController
    layout "admin"

    def new
      redirect_to admin_root_path if session[:user_id] && User.exists?(session[:user_id])
    end

    def create
      user = User.find_by(email: params[:email].to_s.strip.downcase)
      if user&.authenticate(params[:password])
        session[:user_id] = user.id
        redirect_to admin_root_path, notice: "Welcome back."
      else
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:user_id)
      redirect_to admin_login_path, notice: "Signed out."
    end
  end
end
