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
      redirect_to admin_agent_api_path, flash: { api_token: token }
    end

    def revoke_token
      current_store.revoke_api_token!
      redirect_to admin_agent_api_path, notice: "API token revoked."
    end
  end
end
