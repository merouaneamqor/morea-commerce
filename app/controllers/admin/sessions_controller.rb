module Admin
  class SessionsController < ApplicationController
    layout "auth"

    def new
      redirect_to after_login_path if sign_in_allowed?(current_admin_user)
    end

    def create
      email = params[:email].to_s.strip.downcase
      user = sign_in_user(email)

      if sign_in_allowed?(user) && user.authenticate(params[:password])
        return_to = session[:return_to]
        reset_session
        session[:user_id] = user.id
        session[:admin_mode] = user.super_admin? ? "platform" : "store"
        session[:return_to] = return_to if return_to.present?
        redirect_to after_login_path_for(user), notice: t("sign_in.welcome")
      else
        flash.now[:alert] = t("sign_in.invalid")
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: t("sign_in.signed_out")
    end

    private

    def sign_in_allowed?(user)
      user&.can_sign_in?
    end

    def sign_in_user(email)
      unless Store.apex_host?(request.host)
        return current_store&.users&.find_by(email: email) || User.super_admins.find_by(email: email)
      end

      if params[:workspace].present?
        workspace = Store.find_by(slug: params[:workspace].to_s.strip.downcase)
        return workspace&.users&.find_by(email: email)
      end

      # Email uniqueness is per workspace. Require an explicit workspace when
      # the same address has multiple accounts instead of selecting a tenant.
      candidates = User.where(email: email).where("admin = TRUE OR super_admin = TRUE").active.limit(2).to_a
      candidates.first if candidates.one?
    end

    def after_login_path
      after_login_path_for(current_admin_user)
    end

    def after_login_path_for(user)
      return_to = session.delete(:return_to).to_s
      if return_to.start_with?("/") && !return_to.start_with?("//") && !return_to.include?("\\") && !return_to.match?(/[[:cntrl:]]/)
        return return_to
      end

      user&.super_admin? ? admin_platform_path : admin_root_path
    end
  end
end
