# frozen_string_literal: true

module Oauth
  class TokensController < ActionController::API
    include Cors

    before_action :prevent_token_caching

    def preflight
      head :no_content
    end

    def create
      case params[:grant_type]
      when "authorization_code" then authorization_code
      when "refresh_token" then refresh_token
      else
        oauth_error("unsupported_grant_type", "grant_type must be authorization_code or refresh_token")
      end
    end

    private

    def prevent_token_caching
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
    end

    def authorization_code
      payload = Codes.take(params[:code])
      return oauth_error("invalid_grant", "Authorization code is invalid or expired") unless payload
      return oauth_error("invalid_grant", "redirect_uri mismatch") unless payload["redirect_uri"] == params[:redirect_uri]
      return oauth_error("invalid_grant", "client_id mismatch") unless payload["client_id"] == params[:client_id]
      return oauth_error("invalid_grant", "PKCE verification failed") unless Codes.s256?(params[:code_verifier], payload["code_challenge"])

      store = Store.find_by(id: payload["store_id"])
      return oauth_error("invalid_grant", "Store no longer exists") unless store

      render json: token_body(*OauthAccessToken.issue!(store: store, client_id: payload["client_id"]))
    end

    def refresh_token
      pair = OauthAccessToken.rotate!(params[:refresh_token], client_id: params[:client_id])
      return oauth_error("invalid_grant", "Refresh token is invalid or expired") unless pair

      render json: token_body(*pair)
    end

    def token_body(access, refresh)
      {
        access_token: access,
        token_type: "Bearer",
        expires_in: OauthAccessToken::ACCESS_TTL.to_i,
        refresh_token: refresh,
        scope: "catalog"
      }
    end

    def oauth_error(error, description)
      render json: { error: error, error_description: description }, status: :bad_request
    end
  end
end
