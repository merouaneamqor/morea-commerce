module Admin
  # The Seallo Connect app sends the merchant's browser here with the shop, an
  # opaque state and its callback. Staff confirm on this page, then Morea
  # redirects back with a one-time code. Nothing is copied or pasted.
  class SealloConnectionsController < BaseController
    SHOP_PATTERN = /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/
    STATE_MAX_BYTES = 1024

    # Merchants can buy Shopify App Pricing before they have a paid workspace.
    skip_before_action :require_subscription_access!
    prepend_before_action :remember_connection_request, only: :show
    before_action -> { head :not_found unless current_store }
    # Only a connection request needs the app origin and bridge secret; the overview page must still open.
    before_action :require_app_configured!, if: -> { action_name == "create" || connection_request_present? }

    def show
      return authorize_connection if connection_request_present?

      @connections = current_store.store_connections.where(provider: "shopify", shopify_oauth: true).order(:name)
      response.headers["Cache-Control"] = "no-store"
    end

    # Minting happens only on this POST, so a cross-site page cannot make a
    # merchant's browser create a code by navigating to a URL.
    def create
      values = connection_request
      return head :bad_request unless values

      code = SealloConnectionCode.issue!(store: current_store, user: current_user, shop: values[:shop])
      response.headers["Cache-Control"] = "no-store"
      # head avoids Rails' "Redirected to" request log, which would record the code.
      head :found, location: "#{values[:return_to]}?#{URI.encode_www_form(code: code, state: values[:state])}"
    end

    private

    def authorize_connection
      values = connection_request
      return head :bad_request unless values
      raise ActiveRecord::RecordNotFound unless SealloConnectionCode.authorized?(store: current_store, user: current_user)

      @request_values = values
      response.headers["Cache-Control"] = "no-store"
      render :authorize
    end

    # Validates the redirect contract. Only shop and state are used; return_to must
    # equal the app's callback exactly, so no other origin or path is ever reached.
    def connection_request
      shop = string_param(:shop)
      state = string_param(:state)
      return_to = string_param(:return_to)
      return unless shop && shop.bytesize <= 253 && shop.match?(SHOP_PATTERN)
      return unless state.present? && state.bytesize <= STATE_MAX_BYTES
      return unless return_to == callback_url

      { shop: shop, state: state, return_to: return_to }
    end

    def callback_url
      "#{app_origin}/connect/callback"
    end

    def app_origin
      ENV["SEALLO_APP_URL"].to_s.delete_suffix("/")
    end

    def connection_request_present?
      params.key?(:shop) || params.key?(:state) || params.key?(:return_to)
    end

    def string_param(key)
      value = params[key]
      value if value.is_a?(String)
    end

    # Sign-in redirects back here after login. Only the authorization query is kept.
    def remember_connection_request
      return if current_admin_user || !connection_request_present?

      session[:return_to] = request.fullpath
    end

    def require_app_configured!
      return if app_origin.present? && ENV["SEALLO_BRIDGE_SECRET"].to_s.bytesize >= 32

      head :service_unavailable
    end
  end
end
