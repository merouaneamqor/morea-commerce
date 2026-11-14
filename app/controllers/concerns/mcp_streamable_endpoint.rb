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
    self.response_body = rack_body_to_string(body)
  rescue StandardError => e
    Rails.logger.error("[mcp] #{controller_path} #{e.class}: #{e.message}")
    Array(e.backtrace).first(25).each { |line| Rails.logger.error("[mcp]   #{line}") }
    response.set_header("Cache-Control", "no-store")
    render json: {
      jsonrpc: "2.0",
      error: { code: -32603, message: "Internal error" },
      id: mcp_request_id
    }, status: :internal_server_error
  end

  def annotate_mcp_response!
    response.set_header("Cache-Control", "no-store")
    return unless %w[GET HEAD DELETE].include?(request.request_method)

    response.set_header("Allow", "POST")
  end

  def rack_body_to_string(body)
    return body if body.is_a?(String)
    return +"" if body.nil?

    if body.respond_to?(:each) && !body.is_a?(StringIO)
      chunks = +""
      body.each { |chunk| chunks << chunk.to_s }
      body.close if body.respond_to?(:close)
      return chunks
    end

    body.to_s
  end

  def render_mcp_unauthorized!(message: "Unauthorized")
    response.set_header("Cache-Control", "no-store")
    render json: {
      jsonrpc: "2.0",
      error: { code: -32001, message: message },
      id: mcp_request_id
    }, status: :unauthorized
  end

  def render_mcp_subscription_required!
    response.set_header("Cache-Control", "no-store")
    render json: {
      jsonrpc: "2.0",
      error: {
        code: -32003,
        message: "An active subscription is required.",
        data: { code: "subscription_required" }
      },
      id: mcp_request_id
    }, status: :payment_required
  end

  def mcp_request_id
    raw = request.raw_post
    return if raw.blank?

    JSON.parse(raw)["id"]
  rescue JSON::ParserError, TypeError
    nil
  end
end
