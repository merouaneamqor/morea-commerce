# frozen_string_literal: true

module PlatformOauth
  class TokensController < ActionController::API
    include Oauth::Cors
    before_action :prevent_caching

    def preflight
      head :no_content
    end

    def create
      if params.key?(:resource) && params[:resource] != "#{request.base_url}/platform/mcp"
        return oauth_error("invalid_target")
      end
      return oauth_error("invalid_scope") if params[:scope].present? && params[:scope] != "platform"
      return oauth_error("invalid_client") unless OauthClient.exists?(client_id: params[:client_id])

      pair = case params[:grant_type]
      when "authorization_code"
        PlatformOauthCode.exchange!(code: params[:code], client_id: params[:client_id],
          redirect_uri: params[:redirect_uri], code_verifier: params[:code_verifier], resource: "#{request.base_url}/platform/mcp")
      when "refresh_token"
        PlatformOauthToken.rotate!(params[:refresh_token], client_id: params[:client_id], resource: "#{request.base_url}/platform/mcp")
      else
        return oauth_error("unsupported_grant_type")
      end
      return oauth_error("invalid_grant") unless pair

      render json: { access_token: pair[0], refresh_token: pair[1], token_type: "Bearer",
        expires_in: PlatformOauthToken::ACCESS_TTL.to_i, scope: "platform" }
    end

    private

    def prevent_caching
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
    end

    def oauth_error(error)
      render json: { error: error }, status: :bad_request
    end
  end
end
