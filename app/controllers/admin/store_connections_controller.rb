# frozen_string_literal: true

module Admin
  class StoreConnectionsController < BaseController
    before_action :require_workspace!
    before_action :set_connection, only: %i[show update]

    def index
      @connections = current_store.store_connections.order(created_at: :desc).limit(100)
    end

    def new
      @connection = current_store.store_connections.new
      @connection.provider = params[:provider] if StoreConnection::PROVIDERS.include?(params[:provider])
    end

    def create
      @connection = current_store.store_connections.new(connection_params)
      if @connection.save
        redirect_to admin_store_connection_path(@connection), notice: t("connections.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @receipts = @connection.external_order_receipts.order(received_at: :desc).limit(50).includes(:order)
    end

    def update
      # Connection identity and secret cannot be silently replaced underneath an
      # existing import identity. A new provider/store uses a new connection.
      case params[:operation]
      when "disconnect"
        @connection.with_lock { @connection.update!(active: false) }
      when "reconnect"
        @connection.with_lock { @connection.update!(active: true, verified_at: nil, last_error_code: nil) }
      when "rotate_secret"
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
    end

    private

    def require_workspace!
      head :not_found unless current_store
    end

    def set_connection
      @connection = current_store.store_connections.find(params[:id])
    end

    def connection_params
      params.require(:store_connection).permit(:name, :provider, :external_domain, :external_store_id, :webhook_secret)
    end
  end
end
