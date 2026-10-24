# frozen_string_literal: true

module Admin
  class AgentApiController < BaseController
    def show
      @store = current_store
      @mcp_url = "#{request.base_url}/mcp"
      @graphql_url = "#{request.base_url}/graphql"
      @token = flash[:api_token]
    end

    def generate_token
      token = current_store.generate_api_token!
      Audit.record("api_token.generated", actor: current_user, store: current_store, request: request, subject: current_store)
      redirect_to admin_agent_api_path, flash: { api_token: token }
    end

    def revoke_token
      current_store.revoke_api_token!
      Audit.record("api_token.revoked", actor: current_user, store: current_store, request: request, subject: current_store)
      redirect_to admin_agent_api_path, notice: "API token revoked."
    end
  end
end
