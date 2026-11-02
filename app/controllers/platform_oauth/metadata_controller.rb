# frozen_string_literal: true

module PlatformOauth
  class MetadataController < ActionController::API
    include Oauth::Cors

    def protected_resource
      render json: {
        resource: "#{request.base_url}/platform/mcp",
        authorization_servers: [ "#{request.base_url}/platform/oauth" ],
        scopes_supported: [ "platform" ], bearer_methods_supported: [ "header" ]
      }
    end

    def authorization_server
      render json: {
        issuer: "#{request.base_url}/platform/oauth",
        authorization_endpoint: "#{request.base_url}/platform/oauth/authorize",
        token_endpoint: "#{request.base_url}/platform/oauth/token",
        registration_endpoint: "#{request.base_url}/oauth/register",
        response_types_supported: [ "code" ],
        grant_types_supported: [ "authorization_code", "refresh_token" ],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: [ "none" ], scopes_supported: [ "platform" ]
      }
    end
  end
end
