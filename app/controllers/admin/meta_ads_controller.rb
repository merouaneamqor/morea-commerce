# frozen_string_literal: true

module Admin
  # Meta Ads for the current store: connect, choose ad accounts, follow campaigns and map products.
  # Every record is reached through current_store. OAuth callback and the seller UI stay on the
  # platform apex (MetaOauthController + /admin/meta-ads or /publicites).
  class MetaAdsController < BaseController
    include DateRangeSelection

    before_action :require_workspace!
    before_action :set_connection

    def show
      @configured = MetaAds::Oauth.configured?
      @accounts = @connection ? @connection.ad_accounts.where(store_id: current_store.id).order(:name, :meta_ad_account_id) : []
      @date_range = selected_date_range(scope: "meta_ads", default: "last_30")
      @overview = MetaAds::CampaignOverview.new(store: current_store, range: @date_range)
      @ads = linkable_ads
      @products = current_store.products.order(:name).select(:id, :name, :sku)
      @ad_links = MetaAds::ProductLink.where(store_id: current_store.id, object_type: "ad").index_by(&:meta_id)
      @campaign_links = MetaAds::ProductLink.where(store_id: current_store.id, object_type: "campaign").index_by(&:meta_id)
    end

    def connect
      url = MetaAds::Oauth.authorization_url(store: current_store, session: session, user_id: current_user.id)
      redirect_to url, allow_other_host: true, status: :see_other
    rescue MetaAds::Oauth::Error => error
      redirect_to admin_meta_ads_path, alert: t("meta_ads.errors.#{error.code}"), status: :see_other
    end

    def refresh
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.reauthorization_required"), status: :see_other) unless @connection&.active?

      error_code = discover_accounts(@connection)
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.#{error_code}"), status: :see_other) if error_code

      redirect_to admin_meta_ads_path, notice: t("meta_ads.accounts_refreshed"), status: :see_other
    end

    def select_accounts
      return redirect_to(admin_meta_ads_path, alert: t("meta_ads.errors.reauthorization_required"), status: :see_other) unless @connection

      before = @connection.ad_accounts.selected.pluck(:id)
      accounts = MetaAds::AccountSelection.call(connection: @connection, ids: params[:ad_account_ids])
      # Start the first sync (30 day backfill) right away instead of waiting for the next hourly run.
      accounts.select(&:selected?).reject { |account| before.include?(account.id) }.each { |account| MetaAdsSyncJob.perform_later(account.id) }
      redirect_to admin_meta_ads_path, notice: t("meta_ads.selection_saved"), status: :see_other
    rescue MetaAds::AccountSelection::Error => error
      redirect_to admin_meta_ads_path, alert: t("meta_ads.errors.#{error.code}"), status: :see_other
    end

    # Manual campaign / ad to product links. An empty choice removes a link; a manual link replaces an automatic one.
    def product_links
      save_product_links(object_type: "ad", allowed: linkable_ads.index_by(&:meta_id), chosen: link_params(:links))
      save_product_links(object_type: "campaign", allowed: linkable_campaigns.index_by(&:meta_id), chosen: link_params(:campaign_links))
      redirect_to admin_meta_ads_path(**{ from: params[:from], to: params[:to], preset: params[:preset] }.compact_blank),
        notice: t("meta_ads.links_saved"), status: :see_other
    end

    # Asks Meta to revoke the permissions, then removes the token. Synced spend history is kept.
    def disconnect
      revoked = @connection&.revoke_and_disconnect!
      redirect_to admin_meta_ads_path, notice: t(revoked ? "meta_ads.disconnected_revoked" : "meta_ads.disconnected_notice"), status: :see_other
    end

    # Development and test only: connection state and last sync per ad account, without any token.
    def status
      return head :not_found unless Rails.env.local?

      @accounts = @connection ? @connection.ad_accounts.where(store_id: current_store.id).order(:name) : []
      @insight_counts = MetaAds::DailyInsight.where(store_id: current_store.id).group(:ad_account_id, :level).count
      @campaign_count = MetaAds::Campaign.where(store_id: current_store.id).count
    end

    private

    def require_workspace!
      head :not_found unless current_store
    end

    def set_connection
      @connection = current_store&.meta_ads_connection
    end

    # Ads with spend in the last 30 days, for the product mapping screen.
    def linkable_ads
      ids = MetaAds::DailyInsight.where(store_id: current_store.id, level: "ad", date: 30.days.ago.to_date..).distinct.pluck(:ad_id)
      MetaAds::Ad.where(store_id: current_store.id, id: ids).order(:name).limit(200)
    end

    def linkable_campaigns
      MetaAds::Campaign.where(store_id: current_store.id)
        .where(ad_account_id: MetaAds::AdAccount.where(store_id: current_store.id, selected: true).select(:id))
        .order(:name).limit(200)
    end

    def link_params(key)
      raw = params[key]
      raw.respond_to?(:each_pair) ? raw.each_pair.to_h { |meta_id, product_id| [ meta_id.to_s, product_id.to_s ] } : {}
    end

    def save_product_links(object_type:, allowed:, chosen:)
      products = current_store.products.where(id: chosen.values.compact_blank).index_by { |product| product.id.to_s }
      chosen.each do |meta_id, product_id|
        next unless allowed.key?(meta_id)

        link = MetaAds::ProductLink.find_by(store_id: current_store.id, object_type: object_type, meta_id: meta_id)
        if product_id.blank?
          link&.destroy!
        elsif (product = products[product_id.to_s]) && (link.nil? || link.product_id != product.id || link.source != "manual")
          link ||= MetaAds::ProductLink.new(store_id: current_store.id, object_type: object_type, meta_id: meta_id)
          link.update!(product: product, source: "manual")
        end
      end
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
