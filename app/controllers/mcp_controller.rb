# frozen_string_literal: true

class McpController < ActionController::API
  include Api::TokenAuthenticatable

  def handle
    server = CatalogServer.build(store: current_api_store)
    # Public endpoint: DNS-rebinding checks only allow loopback hosts. Auth is the bearer token.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      dns_rebinding_protection: false,
      serve_subscriptions_listen: false,
      max_request_bytes: 48.megabytes
    )
    status, headers, body = transport.handle_request(request)

    self.status = status
    headers.each { |key, value| response.set_header(key, value) }
    self.response_body = body
  end
end
