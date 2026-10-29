# frozen_string_literal: true

module Admin
  class StoreConnectionsController < BaseController
    before_action :require_workspace!
    before_action :set_shopify_configuration
    before_action :set_connection, only: %i[show update destroy]

    def index
      @connections = current_store.store_connections.order(created_at: :desc).limit(100)
    end

    def new
      @connection = current_store.store_connections.new
      @connection.provider = params[:provider] if StoreConnection::PROVIDERS.include?(params[:provider])
      # App launches may suggest a domain, but only the submitted form and OAuth
      # approval can connect it. Never prefill credentials or tenant identity.
      shop = params[:shop]
      if @connection.provider == "shopify" && shop.is_a?(String) && shop.bytesize <= 253 && shop.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)
        @connection.external_domain = shop
      end
    end

    def create
      @connection = current_store.store_connections.new(connection_params)
      if @connection.provider == "shopify" && !@shopify_configured
        @connection.errors.add(:base, t("connections.shopify_api.errors.config_missing"))
        return render :new, status: :unprocessable_entity
      end
      @connection.shopify_oauth = true if @connection.provider == "shopify"
      if @connection.save
        if @connection.provider == "shopify"
          return redirect_to shopify_authorization_url, allow_other_host: true, status: :see_other
        end
        redirect_to admin_store_connection_path(@connection), notice: t("connections.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @receipts = @connection.external_order_receipts.order(received_at: :desc).limit(50).includes(:order)
    end

    def destroy
      if @connection.with_lock { @connection.destroy }
        redirect_to admin_store_connections_path, notice: t("connections.deleted"), status: :see_other
      else
        redirect_to admin_store_connection_path(@connection), alert: t("connections.delete_blocked"), status: :see_other
      end
    end

    def shopify_callback
      @connection, code = Connections::ShopifyOauth.consume_callback!(query_string: request.query_string,
        session: session, store: current_store, user_id: current_user.id)
      Connections::ShopifyApi.new(connection: @connection).authorize!(code: code)
      ShopifyOrdersSyncJob.perform_later(@connection.id)
      redirect_to admin_store_connection_path(@connection), notice: t("connections.shopify_api.verified")
    rescue Connections::ShopifyOauth::Error, Connections::ShopifyApi::Error => error
      @oauth_error_code = error.code
      render :oauth_error, status: :unprocessable_entity
    end

    def update
      # Connection identity and secret cannot be silently replaced underneath an
      # existing import identity. A new provider/store uses a new connection.
      case params[:operation]
      when "disconnect"
        @connection.with_lock do
          @connection.update!(active: false, shopify_access_token: nil, shopify_refresh_token: nil,
            shopify_access_token_expires_at: nil, shopify_refresh_token_expires_at: nil,
            shopify_api_verified_at: nil, shopify_granted_scopes: [], shopify_oauth_state_digest: nil, shopify_oauth_state_expires_at: nil)
        end
      when "reconnect"
        @connection.with_lock { @connection.update!(active: true, verified_at: nil, last_error_code: nil, shopify_api_verified_at: nil) }
      when "authorize_shopify"
        return head :unprocessable_entity unless @connection.provider == "shopify"

        return redirect_to shopify_authorization_url, allow_other_host: true, status: :see_other
      when "verify_shopify_api"
        return head :unprocessable_entity unless @connection.provider == "shopify"

        Connections::ShopifyApi.new(connection: @connection).verify!
        ShopifyOrdersSyncJob.perform_later(@connection.id)
        return redirect_to admin_store_connection_path(@connection), notice: t("connections.shopify_api.verified")
      when "sync_shopify_orders"
        unless @shopify_configured
          raise Connections::ShopifyApi::Error.new("config_missing")
        end

        count = Connections::ShopifySyncRequest.call(store: current_store, connection_id: @connection.id)
        return redirect_to admin_store_connection_path(@connection), notice: t("shopify_sync.queued", count: count), status: :see_other
      when "rotate_secret"
        return head :unprocessable_entity if @connection.provider == "shopify"

        @connection.with_lock do
          @connection.update!(webhook_secret: params.require(:store_connection).permit(:webhook_secret)[:webhook_secret],
            verified_at: nil, last_error_code: nil)
        end
      else
        return head :unprocessable_entity
      end
      redirect_to admin_store_connection_path(@connection), notice: t("connections.updated")
    rescue ActiveRecord::RecordInvalid
      @receipts = @connection.external_order_receipts.order(received_at: :desc).limit(50).includes(:order)
      render :show, status: :unprocessable_entity
    rescue Connections::ShopifyApi::Error, Connections::ShopifyOauth::Error, Connections::ShopifySyncRequest::Error => error
      @connection.reload
      @connection.errors.add(:base, t("connections.shopify_api.errors.#{error.code}"))
      @receipts = @connection.external_order_receipts.order(received_at: :desc).limit(50).includes(:order)
      render :show, status: :unprocessable_entity
    end

    private

    def set_shopify_configuration
      @shopify_configured = Connections::ShopifyOauth.configured?
    end

    def shopify_authorization_url
      callback = admin_shopify_callback_url(host: Store.base_domain, protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
      Connections::ShopifyOauth.authorization_url(connection: @connection, session: session, user_id: current_user.id, callback_url: callback)
    end

    def require_workspace!
      head :not_found unless current_store
    end

    def set_connection
      @connection = current_store.store_connections.find(params[:id])
    end

    def connection_params
      input = params.require(:store_connection)
      fields = input[:provider] == "shopify" ? [] : %i[external_store_id webhook_secret]
      input.permit(:name, :provider, :external_domain, *fields)
    end
  end
end
