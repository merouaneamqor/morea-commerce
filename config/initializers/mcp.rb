# frozen_string_literal: true

# The MCP gem swallows tool exceptions and returns JSON-RPC -32603 unless a
# reporter is configured. Log the real failure so Render shows the stack.
MCP.configure do |config|
  config.exception_reporter = lambda do |exception, server_context|
    context = server_context.is_a?(Hash) ? server_context.except(:store, :user) : {}
    Rails.logger.error("[mcp] #{exception.class}: #{exception.message} context=#{context.inspect}")
    Array(exception.backtrace).first(25).each { |line| Rails.logger.error("[mcp]   #{line}") }
  end
end
