# frozen_string_literal: true

class McpController < ActionController::API
  include Api::TokenAuthenticatable
  include McpStreamableEndpoint

  def handle
    # Public endpoint: DNS-rebinding checks only allow loopback hosts. Auth is the bearer token.
    serve_mcp(CatalogServer.build(store: current_api_store), max_request_bytes: 48.megabytes)
  end
end
