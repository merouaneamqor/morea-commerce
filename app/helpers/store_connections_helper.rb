module StoreConnectionsHelper
  def connection_state(connection)
    return t("connections.states.disconnected") unless connection.active?
    if connection.provider == "shopify"
      return t("connections.states.attention") if connection.shopify_api_error_code.present?
      return t("connections.shopify_api.states.connected") if connection.shopify_api_connected?

      return t(connection.shopify_api_configured? ? "connections.shopify_api.states.configured" : "connections.shopify_api.states.missing")
    end
    return t("connections.states.attention") if connection.last_error_code.present?

    connection.verified_at? ? t("connections.states.verified") : t("connections.states.awaiting")
  end

  def connection_webhook_url(connection)
    store_orders_webhook_url(token: connection.token, host: Store.base_domain,
      protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
  end
end
