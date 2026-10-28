# frozen_string_literal: true

module Admin
  # Read-only Meta Ads connection for the current store. Every record is reached through current_store.
  class MetaAdsController < BaseController
    before_action :require_workspace!
    before_action :set_connection, except: :callback

    def show
      @configured = MetaAds::Oauth.configured?
      @accounts = @connection ? @connection.ad_accounts.where(store_id: current_store.id).order(:name, :meta_ad_account_id) : []
    end

    def connect
      url = MetaAds::Oauth.authorization_url(store: current_store, session: session, user_id: current_user.id, callback_url: callback_url)
      redirect_to url, allow_other_host: true, status: :see_other
    rescue MetaAds::Oauth::Error => error
      redirect_to admin_meta_ads_path, alert: t("meta_ads.errors.#{error.code}"), status: :see_other
    end

    def callback
      connection, code = MetaAds::Oauth.consume_callback!(params: params, session: session, store: current_store, user_id: current_user.id)
      MetaAds::Authorizer.new(connection: connection, redirect_uri: callback_url).authorize!(code: code)
      error_code = discover_accounts(connection)
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.#{error_code}")) if error_code

      redirect_to admin_meta_ads_path, notice: t("meta_ads.connected")
    rescue MetaAds::Oauth::Error => error
      redirect_to admin_meta_ads_path, alert: t("meta_ads.errors.#{error.code}")
    end

    def refresh
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.reauthorization_required"), status: :see_other) unless @connection&.active?

      error_code = discover_accounts(@connection)
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.#{error_code}"), status: :see_other) if error_code

      redirect_to admin_meta_ads_path, notice: t("meta_ads.accounts_refreshed"), status: :see_other
    end

    def select_accounts
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.reauthorization_required"), status: :see_other) unless @connection

      MetaAds::AccountSelection.call(connection: @connection, ids: params[:ad_account_ids])
      redirect_to admin_meta_ads_path, notice: t("meta_ads.selection_saved"), status: :see_other
    rescue MetaAds::AccountSelection::Error => error
      redirect_to admin_meta_ads_path, alert: t("meta_ads.errors.#{error.code}"), status: :see_other
    end

    def disconnect
      @connection&.disconnect!
      redirect_to admin_meta_ads_path, notice: t("meta_ads.disconnected_notice"), status: :see_other
    end

    private

    def require_workspace!
      head :not_found unless current_store
    end

    def set_connection
      @connection = current_store.meta_ads_connection
    end

    def callback_url
      admin_meta_ads_callback_url(host: Store.base_domain, protocol: Rails.env.local? ? "http" : "https", port: ENV["APP_PORT"].presence)
    end

    # Revoked or expired tokens and removed permissions send the merchant back through Meta Login.
    # Returns nil on success or the error code to show.
    def discover_accounts(connection)
      MetaAds::AccountDiscovery.new(connection: connection).call
      nil
    rescue MetaAds::Client::AuthError, MetaAds::Client::PermissionError => error
      connection.mark_needs_reauthorization!(error.code)
      "reauthorization_required"
    rescue MetaAds::Client::Error
      "unavailable"
    end
  end
end
