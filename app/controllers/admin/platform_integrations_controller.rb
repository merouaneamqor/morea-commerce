# frozen_string_literal: true

module Admin
  # Cross-workspace integration health. GET pages are provider-free; rechecks are
  # explicit and never import orders or reactivate disconnected shops.
  class PlatformIntegrationsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_store, only: %i[show recheck]

    RecheckResult = Struct.new(:code, :success, keyword_init: true) do
      def success?
        success
      end
    end

    def index
      diagnostics = Platform::IntegrationDiagnostics.new(actor: current_user)
      @failing = diagnostics.failing_entries
      @workspaces = diagnostics.workspaces
    end

    def show
      @workspace = Platform::IntegrationDiagnostics.new(actor: current_user).workspace(@store)
    end

    def recheck
      result = perform_recheck
      Platform::AdminAudit.record(
        action: "integration.recheck",
        actor: current_user,
        store: @store,
        subject: recheck_subject,
        ip: request.remote_ip,
        surface: "platform_integrations",
        provider: recheck_provider,
        connection_id: params[:connection_id].presence&.to_i,
        outcome: result.code
      )
      message = t("platform_admin.integrations.outcomes.#{result.code}",
        default: t("platform_admin.integrations.outcomes.unavailable"))
      if result.success?
        redirect_to admin_platform_integration_path(@store), notice: message
      else
        redirect_to admin_platform_integration_path(@store), alert: message
      end
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_store
      @store = Store.find(params[:id])
    end

    def recheck_provider
      params[:provider].presence || params[:kind].to_s
    end

    def recheck_subject
      case params[:kind].to_s
      when "store_connection"
        @store.store_connections.find_by(id: params[:connection_id])
      when "meta_ads"
        MetaAds::Connection.find_by(store_id: @store.id, id: params[:connection_id])
      when "sendit"
        @store.delivery_accounts.find_by(provider: "sendit", id: params[:connection_id])
      when "sendit_legacy"
        @store
      end
    end

    def perform_recheck
      case params[:kind].to_s
      when "store_connection" then recheck_store_connection
      when "meta_ads" then recheck_meta_ads
      when "sendit" then recheck_sendit_account
      when "sendit_legacy" then recheck_sendit_legacy
      else RecheckResult.new(code: "unsupported", success: false)
      end
    end

    def recheck_store_connection
      connection = @store.store_connections.find(params.require(:connection_id))
      if connection.provider == "shopify" && connection.shopify_app == "seallo_connect" && connection.shopify_oauth?
        result = Platform::SealloDiagnostics.new(actor: current_user).recheck(connection: connection)
        return RecheckResult.new(code: result.code, success: result.success?)
      end

      recheck_manual_store_connection(connection)
    end

    # WooCommerce / YouCan: refresh local verified state only.
    # Never imports orders, never reactivates a disconnected connection.
    def recheck_manual_store_connection(connection)
      connection.reload
      return RecheckResult.new(code: "disconnected", success: false) unless connection.active?

      if connection.provider == "shopify" && connection.shopify_oauth?
        return RecheckResult.new(code: "unsupported_connection", success: false)
      end

      unless connection.read_attribute(:webhook_secret_ciphertext).present?
        connection.update!(last_error_code: "credentials_missing")
        return RecheckResult.new(code: "credentials_missing", success: false)
      end

      connection.update!(verified_at: Time.current, last_error_code: nil)
      RecheckResult.new(code: "verified", success: true)
    end

    def recheck_meta_ads
      connection = MetaAds::Connection.find_by!(store_id: @store.id, id: params.require(:connection_id))
      return RecheckResult.new(code: "disconnected", success: false) if connection.status == "disconnected"
      return RecheckResult.new(code: "needs_reauthorization", success: false) unless connection.active?

      MetaAds::Client.new(connection: connection).get("me", fields: "id")
      connection.update!(last_verified_at: Time.current, last_error_code: nil)
      RecheckResult.new(code: "verified", success: true)
    rescue MetaAds::Client::AuthError, MetaAds::Client::PermissionError => error
      connection.mark_needs_reauthorization!(error.code)
      RecheckResult.new(code: error.code, success: false)
    rescue MetaAds::Client::Error => error
      connection.update!(last_error_code: error.code)
      RecheckResult.new(code: error.code, success: false)
    rescue ArgumentError
      RecheckResult.new(code: "credentials_missing", success: false)
    end

    def recheck_sendit_account
      account = @store.delivery_accounts.find_by!(provider: "sendit", id: params.require(:connection_id))
      return RecheckResult.new(code: "disconnected", success: false) unless account.is_active?

      keys = account.credentials
      public_key = keys["api_key"].to_s
      secret_key = keys["api_secret"].to_s
      return RecheckResult.new(code: "credentials_missing", success: false) if public_key.blank? || secret_key.blank?

      Sendit::Client.verify!(@store, public_key: public_key, secret_key: secret_key)
      account.update!(connected_at: Time.current)
      RecheckResult.new(code: "verified", success: true)
    rescue Sendit::Client::Error => error
      RecheckResult.new(code: sendit_safe_code(error), success: false)
    end

    def recheck_sendit_legacy
      public_key = @store[:sendit_public_key].to_s
      secret_key = @store[:sendit_secret_key].to_s
      return RecheckResult.new(code: "credentials_missing", success: false) if public_key.blank? || secret_key.blank?

      Sendit::Client.verify!(@store, public_key: public_key, secret_key: secret_key)
      RecheckResult.new(code: "verified", success: true)
    rescue Sendit::Client::Error => error
      RecheckResult.new(code: sendit_safe_code(error), success: false)
    end

    def sendit_safe_code(error)
      kind = error.kind.to_s
      %w[invalid_keys blocked network unexpected rejected].include?(kind) ? kind : "unavailable"
    end
  end
end
