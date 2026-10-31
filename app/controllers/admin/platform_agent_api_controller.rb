# frozen_string_literal: true

module Admin
  class PlatformAgentApiController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :prepare_page

    def show
    end

    def generate_token
      @token = PlatformApiToken.issue!(user: current_user)
      load_grant
      # Never place the bearer secret in flash or the cookie-backed session.
      render :show, status: :ok
    end

    def revoke_token
      current_user.with_lock do
        PlatformApiToken.where(user: current_user, revoked_at: nil).update_all(revoked_at: Time.current)
      end
      redirect_to admin_platform_agent_api_path, notice: "Platform token revoked.", status: :see_other
    end

    def revoke_connections
      current_user.with_lock do
        PlatformOauthToken.where(user: current_user, revoked_at: nil).update_all(revoked_at: Time.current)
        PlatformOauthCode.where(user: current_user).delete_all
      end
      redirect_to admin_platform_agent_api_path, notice: "Agent connections revoked.", status: :see_other
    end

    private

    def prepare_page
      session[:admin_mode] = "platform"
      response.set_header("Cache-Control", "no-store")
      @mcp_url = "#{request.base_url}/platform/mcp"
      load_grant
    end

    def load_grant
      @grant = PlatformApiToken.where(user: current_user, revoked_at: nil).where("expires_at > ?", Time.current).first
    end
  end
end
