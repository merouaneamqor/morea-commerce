module Api
  # Token exchange for the WordPress plugin. There is no shared key: the one-time
  # code plus the PKCE verifier (known only to the plugin instance that started
  # the request) authorize it, and a code is consumed on first use.
  class WoocommerceController < ActionController::API
    include ActionController::RateLimiting
    wrap_parameters false
    rate_limit to: 20, within: 1.minute, by: -> { request.remote_ip }, only: :connect,
      with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

    def connect
      result = Connections::WoocommerceConnect.call(code: params[:code], code_verifier: params[:code_verifier], site: params[:site])
      response.headers["Cache-Control"] = "no-store"
      render json: { delivery_url: delivery_url(result.connection), secret: result.secret, workspace_name: result.connection.store.name }
    rescue Connections::WoocommerceConnect::Error => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def delivery_url(connection)
      store_orders_webhook_url(token: connection.token, host: Store.base_domain,
        protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
    end
  end
end
