# frozen_string_literal: true

class PlatformMcpController < ActionController::API
  before_action :authenticate_platform_token!
  rescue_from PlatformTools::Unauthorized do
    response.set_header("Cache-Control", "no-store")
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def handle
    server = PlatformServer.build(user: @platform_user)
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      dns_rebinding_protection: false,
      serve_subscriptions_listen: false,
      max_request_bytes: 1.megabyte
    )
    status, headers, body = transport.handle_request(request)
    self.status = status
    headers.each { |key, value| response.set_header(key, value) }
    response.set_header("Cache-Control", "no-store")
    self.response_body = body
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
