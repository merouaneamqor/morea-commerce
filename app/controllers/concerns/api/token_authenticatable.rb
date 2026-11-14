# frozen_string_literal: true

module Api
  module TokenAuthenticatable
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_api_token!
    end

    private

    def current_api_store
      @current_api_store
    end

    def authenticate_api_token!
      token = bearer_token
      store = Store.find_by_api_token(token) || OauthAccessToken.authenticate(token)&.store
      if store
        unless store.operational_access?
          render_api_subscription_required!
          return
        end
        @current_api_store = store
        Current.store = store
        return
      end

      response.set_header("WWW-Authenticate", %(Bearer realm="morea", resource_metadata="#{request.base_url}/.well-known/oauth-protected-resource/mcp"))
      render_api_unauthorized!
    end

    # GraphQL and other JSON APIs keep the { errors: [...] } shape. MCP overrides
    # these to return JSON-RPC so clients do not map a bare 401 body to -32603.
    def render_api_unauthorized!
      render json: { errors: [ { message: "Unauthorized" } ] }, status: :unauthorized
    end

    def render_api_subscription_required!
      render json: {
        errors: [ { message: "An active subscription is required.", code: "subscription_required" } ]
      }, status: :payment_required
    end

    def bearer_token
      header = request.authorization.to_s
      scheme, token = header.split(" ", 2)
      return if scheme.to_s.casecmp("bearer").nonzero? || token.blank?

      token
    end
  end
end
