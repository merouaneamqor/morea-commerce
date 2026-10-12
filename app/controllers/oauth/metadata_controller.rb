# frozen_string_literal: true

module Oauth
  class MetadataController < ActionController::API
    include Cors

    def protected_resource
      render json: {
        resource: "#{request.base_url}/mcp",
        authorization_servers: [ request.base_url ],
        scopes_supported: [ "catalog" ],
        bearer_methods_supported: [ "header" ]
      }
    end

    def authorization_server
      render json: {
        issuer: request.base_url,
        authorization_endpoint: oauth_authorize_url,
        token_endpoint: oauth_token_url,
        registration_endpoint: oauth_register_url,
        response_types_supported: [ "code" ],
        grant_types_supported: [ "authorization_code", "refresh_token" ],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: [ "none" ],
        scopes_supported: [ "catalog" ]
      }
    end

    private

    def oauth_authorize_url
      "#{request.base_url}/oauth/authorize"
    end

    def oauth_token_url
      "#{request.base_url}/oauth/token"
    end

    def oauth_register_url
      "#{request.base_url}/oauth/register"
    end
  end
end
