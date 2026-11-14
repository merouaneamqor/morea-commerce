# frozen_string_literal: true

class PlatformMcpController < ActionController::API
  include McpStreamableEndpoint

  before_action :authenticate_platform_token!
  rescue_from PlatformTools::Unauthorized do
    response.set_header("Cache-Control", "no-store")
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def handle
    serve_mcp(PlatformServer.build(user: @platform_user), max_request_bytes: 1.megabyte)
  end

  private

  def authenticate_platform_token!
    scheme, secret = request.authorization.to_s.split(" ", 2)
    if scheme.to_s.casecmp("Bearer").zero?
      grant = PlatformApiToken.authenticate(secret) || PlatformOauthToken.authenticate(secret)
      grant = nil if grant.is_a?(PlatformOauthToken) && grant.resource != "#{request.base_url}/platform/mcp"
    end
    if grant
      @platform_user = grant.user
      return
    end

    response.set_header("WWW-Authenticate", %(Bearer realm="morea-platform", resource_metadata="#{request.base_url}/.well-known/oauth-protected-resource/platform/mcp"))
    response.set_header("Cache-Control", "no-store")
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
