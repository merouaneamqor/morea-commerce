module Admin
  class SessionsController < ApplicationController
    layout "admin"

    def new
      redirect_to after_login_path if current_admin_user
    end

    def create
      email = params[:email].to_s.strip.downcase
      return throttled if throttled?(email)

      user = current_store&.users&.find_by(email: email) || User.super_admins.find_by(email: email)

      if user&.authenticate(params[:password])
        sign_in(user)
        redirect_to after_login_path_for(user), notice: "Welcome back."
      else
        Audit.record("auth.sign_in_failed", store: current_store, request: request, platform: false,
          metadata: { email_digest: Audit.email_digest(email) })
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      if (admin_session = current_admin_session)
        Audit.record("auth.sign_out", actor: current_admin_user, store: current_store, request: request, subject: admin_session)
        admin_session.revoke!
      end
      reset_session
      redirect_to admin_login_path, notice: "Signed out."
    end

    private

    MAX_FAILURES_PER_EMAIL = 10
    MAX_FAILURES_PER_IP = 30
    FAILURE_WINDOW = 15.minutes

    # Rotate the session id on login (fixation defence) but keep storefront state the visitor already had.
    def sign_in(user)
      keep = session.to_h.slice("cart_token", "last_delivery", "return_to")
      reset_session
      keep.each { |key, value| session[key] = value }

      admin_session, token = AdminSession.start!(
        user: user, store: user.super_admin? ? current_store : user.store,
        ip: request.remote_ip, user_agent: request.user_agent
      )
      session[:admin_session_token] = token
      session[:admin_mode] = user.super_admin? ? "platform" : "store"
      Audit.record("auth.sign_in", actor: user, store: current_store, request: request, subject: admin_session)
    end

    def throttled?(email)
      recent = AuditEvent.where(action: "auth.sign_in_failed").where("created_at > ?", FAILURE_WINDOW.ago)
      recent.where("metadata ->> 'email_digest' = ?", Audit.email_digest(email)).count >= MAX_FAILURES_PER_EMAIL ||
        recent.where(ip: request.remote_ip).count >= MAX_FAILURES_PER_IP
    end

    def throttled
      flash.now[:alert] = "Too many attempts. Try again later."
      render :new, status: :too_many_requests
    end

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
