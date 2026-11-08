# frozen_string_literal: true

# Browser side of Meta Login on the platform apex: the one redirect URI registered with Meta
# (META_REDIRECT_URI = https://<apex>/auth/meta/callback) and the public deletion status page.
# After the code is exchanged, the merchant stays on the apex seller admin to choose ad accounts.
class MetaOauthController < ApplicationController
  layout "bare"
  before_action :require_platform_host!

  def callback
    pending = MetaAds::Oauth.pending_for(params: params, session: session)
    code = MetaAds::Oauth.consume!(pending: pending, params: params, session: session)
    MetaAds::Authorizer.new(connection: pending.connection).authorize!(code: code)
    error = discover_accounts(pending.connection)
    back_to(pending.store, error ? { alert: t("meta_ads.errors.#{error}") } : { notice: t("meta_ads.connected") })
  rescue MetaAds::Oauth::Error => failure
    # The state was valid when we know the store: send the merchant home with the reason. Otherwise show it here.
    store = pending&.store
    return back_to(store, alert: t("meta_ads.errors.#{failure.code}")) if store

    @message = t("meta_ads.errors.#{failure.code}")
    render :error, status: :bad_request
  end

  def deletion_status
    @request = MetaAds::DeletionRequest.find_by(confirmation_code: params[:code])
    return render(:error, status: :not_found) unless @request

    render :deletion_status
  end

  private

  def require_platform_host!
    head :not_found unless Store.apex_host?(request.host)
  end

  # Returns nil, or the error code to show.
  def discover_accounts(connection)
    MetaAds::AccountDiscovery.new(connection: connection).call
    nil
  rescue MetaAds::Client::AuthError, MetaAds::Client::PermissionError => error
    connection.mark_needs_reauthorization!(error.code)
    "reauthorization_required"
  rescue MetaAds::Client::Error
    "unavailable"
  end

  def back_to(store, flash_options)
    flash_options.each { |type, message| flash[type] = message }
    # Seller admin lives on the apex host; pin the workspace for super-admins who entered a store.
    session[:admin_mode] = "store"
    session[:admin_store_id] = store.id
    redirect_to admin_meta_ads_path, status: :see_other
  end
end
