module StoreConnectionsHelper
  def connection_state(connection)
    return t("connections.states.disconnected") unless connection.active?
    return t("connections.states.attention") if connection.last_error_code.present?

    connection.verified_at? ? t("connections.states.verified") : t("connections.states.awaiting")
  end

  def connection_webhook_url(connection)
    store_orders_webhook_url(token: connection.token, host: Store.base_domain,
      protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
  end
end
