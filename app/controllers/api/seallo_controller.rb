module Api
  class SealloController < ActionController::API
    wrap_parameters false
    before_action :authenticate_bridge!

    def connect
      connection = Connections::SealloConnect.call(code: params[:code], shop: params[:shop])
      render json: present(connection)
    rescue Connections::SealloConnect::Error => error
      render json: { error: error.message }, status: :unprocessable_entity
    rescue Connections::ShopifyApi::Error => error
      render json: { error: error.code }, status: :unprocessable_entity
    rescue Connections::SealloBridge::Error => error
      render json: { error: error.message }, status: :service_unavailable
    end

    def status
      connection = scoped_connection
      render json: connection ? present(connection) : { connected: false, state: "unlinked" }
    end

    def sync
      connection = scoped_connection
      return render json: { error: "disconnected" }, status: :conflict unless connection&.active?
      if connection.shopify_app == "seallo_connect" && !Connections::SealloEntitlement.refresh!(connection)
        return render json: { error: "subscription_required" }, status: :payment_required
      end
      return render json: { error: "subscription_required" }, status: :payment_required unless connection.store.operational_access?

      ShopifyOrdersSyncJob.perform_later(connection.id)
      render json: present(connection).merge(sync_status: "queued")
    rescue Connections::SealloBridge::Error => error
      render json: { error: error.message }, status: :service_unavailable
    end

    def disconnect
      connection = scoped_connection
      connection&.with_lock { connection.update!(active: false, shopify_api_verified_at: nil) }
      render json: { connected: false, state: "disconnected" }
    end

    private

    def authenticate_bridge!
      Connections::SealloBridge.authenticate!(body: request.raw_post, timestamp: request.headers["X-Seallo-Timestamp"], signature: request.headers["X-Seallo-Signature"])
      render json: { error: "invalid_operation" }, status: :unprocessable_entity unless params[:operation] == action_name
    rescue Connections::SealloBridge::Error => error
      render json: { error: error.message }, status: error.message == "config_missing" ? :service_unavailable : :unauthorized
    end

    def scoped_connection
      StoreConnection.find_by(provider: "shopify", shopify_app: "seallo_connect", external_domain: params[:shop].to_s)
    end

    def present(connection)
      { connected: connection.shopify_api_connected?, workspace_name: connection.store.name,
        state: connection.connection_state, last_sync_at: connection.shopify_orders_synced_at,
        sync_status: connection.shopify_sync_state, error: connection.shopify_sync_error || connection.shopify_api_error_code,
        plan_name: connection.shopify_plan_name, order_limit: connection.shopify_order_limit,
        orders_used: Connections::SealloAllowance.used(connection),
        imported: connection.shopify_sync_counts["imported"], rejected: connection.shopify_sync_counts["rejected"], replayed: connection.shopify_sync_counts["replayed"] }
    end
  end
end
