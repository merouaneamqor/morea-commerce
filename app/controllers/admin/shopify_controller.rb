# frozen_string_literal: true

module Admin
  # Shopify's App URL opens Morea outside Shopify admin. A shop query parameter
  # is only a display hint: login and the existing POST/OAuth flow establish access.
  class ShopifyController < BaseController
    prepend_before_action :remember_installation
    before_action :require_workspace!

    def show
      @shop = shop_hint
      @connections = current_store.store_connections.where(provider: "shopify")
      @connections = @connections.where(external_domain: @shop) if @shop
      @connections = @connections.order(created_at: :desc).limit(100)
    end

    private

    def shop_hint
      value = params[:shop]
      value if value.is_a?(String) && value.bytesize <= 253 && value.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)
    end

    def remember_installation
      return if current_admin_user

      session[:return_to] = admin_shopify_path(shop: shop_hint)
    end

    def require_workspace!
      head :not_found unless current_store
    end
  end
end
