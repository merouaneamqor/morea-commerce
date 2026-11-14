# frozen_string_literal: true

# Shared Streamable HTTP wiring for merchant `/mcp` and platform `/platform/mcp`.
# Stateless JSON replies only need `Accept: application/json`; GET is rejected with Allow: POST.
module McpStreamableEndpoint
  extend ActiveSupport::Concern

  private

  def serve_mcp(server, max_request_bytes:)
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      dns_rebinding_protection: false,
      serve_subscriptions_listen: false,
      max_request_bytes: max_request_bytes
    )
    status, headers, body = transport.handle_request(request)
    self.status = status
    headers.each { |key, value| response.set_header(key, value) }
    annotate_mcp_response!
    self.response_body = body
  rescue StandardError => e
    Rails.logger.error("[mcp] #{controller_path} #{e.class}: #{e.message}")
    response.set_header("Cache-Control", "no-store")
    render json: {
      jsonrpc: "2.0",
      error: { code: -32603, message: "Internal error" },
      id: nil
    }, status: :internal_server_error
  end

  def annotate_mcp_response!
    response.set_header("Cache-Control", "no-store")
    return unless %w[GET HEAD DELETE].include?(request.request_method)

    response.set_header("Allow", "POST")
  end
end
