# frozen_string_literal: true

module Admin
  # Leaves a workspace that a super admin opened as one of its members.
  class ImpersonationsController < BaseController
    skip_before_action :confine_confirmation_agents!
    skip_before_action :require_subscription_access!

    def destroy
      unless session[:impersonator_id].present?
        return redirect_to(current_user ? admin_root_path : admin_login_path)
      end

      impersonator = User.super_admins.active.find_by(id: session[:impersonator_id])
      unless impersonator && session[:impersonator_session_version].to_i == impersonator.session_version
        reset_session
        return redirect_to admin_login_path, alert: t("sign_in.signed_out")
      end

      session[:user_id] = impersonator.id
      session[:session_version] = impersonator.session_version
      session.delete(:impersonator_id)
      session.delete(:impersonator_session_version)
      session[:admin_mode] = "platform"
      session.delete(:admin_store_id)
      redirect_to admin_platform_path, notice: t("platform_admin.impersonate.stopped")
    end
  end
end
