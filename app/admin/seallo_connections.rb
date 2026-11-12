# frozen_string_literal: true

ActiveAdmin.register_page "Seallo Connections", namespace: :superadmin do
  menu priority: 2, label: "Seallo connections"

  controller do
    before_action :load_diagnostics, only: :index

    private

    def load_diagnostics
      @query = params[:q].to_s.strip.first(200)
      @page = [ params[:page].to_i, 1 ].max
      connections = StoreConnection.where(provider: "shopify", shopify_app: "seallo_connect", shopify_oauth: true).joins(:store)
      authorizations = SealloConnectionCode.where(consumed_at: nil).where(created_at: 24.hours.ago..).joins(:store)
      if @query.present?
        match = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        connections = connections.where("stores.name ILIKE :q OR stores.slug ILIKE :q OR store_connections.external_domain ILIKE :q", q: match)
        authorizations = authorizations.where("stores.name ILIKE :q OR stores.slug ILIKE :q OR seallo_connection_codes.shop_domain ILIKE :q", q: match)
      end
      # Select only the fields rendered here; provider secrets are never loaded.
      @connections = connections.select(:id, :store_id, :external_domain, :active, :shopify_plan_name,
        :shopify_order_limit, :shopify_billing_period_start, :shopify_billing_period_end,
        :shopify_entitled_until, :shopify_api_verified_at, :shopify_api_error_code,
        :shopify_sync_error, :shopify_orders_synced_at, :shopify_sync_state)
        .includes(:store).order(id: :desc).offset((@page - 1) * 25).limit(26).to_a
      @has_next_page = @connections.length > 25
      @connections = @connections.first(25)
      @authorizations = authorizations.select(:id, :store_id, :shop_domain, :created_at, :expires_at)
        .includes(:store).order(created_at: :desc, id: :desc).limit(10).to_a
    end
  end

  content title: "Seallo connections" do
    para do
      text_node "For Shopify, WooCommerce, YouCan, Meta Ads and Sendit together, open "
      text_node link_to("Integration diagnostics", admin_platform_integrations_path)
      text_node "."
    end
    render partial: "admin/seallo_connections/diagnostics"
  end

  page_action :recheck, method: :post do
    connection = StoreConnection.where(provider: "shopify", shopify_app: "seallo_connect", shopify_oauth: true).find(params.require(:connection_id))
    result = Platform::SealloDiagnostics.new(actor: current_admin_user).recheck(connection: connection)
    redirect_to superadmin_seallo_connections_path, flash: { (result.success? ? :notice : :alert) => result.message }
  end

  page_action :diagnose_link, method: :post do
    authorization = SealloConnectionCode.where(consumed_at: nil).where(created_at: 24.hours.ago..).find(params.require(:authorization_id))
    result = Platform::SealloDiagnostics.new(actor: current_admin_user).diagnose_link(authorization: authorization)
    redirect_to superadmin_seallo_connections_path, flash: { (result.success? ? :notice : :alert) => result.message }
  end
end
