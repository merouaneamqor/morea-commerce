module Admin
  class SealloConnectionsController < BaseController
    # Merchants can buy Shopify App Pricing before they have a paid workspace.
    skip_before_action :require_subscription_access!
    before_action -> { head :not_found unless current_store }

    def show
      @connections = current_store.store_connections.where(shopify_app: "seallo_connect").order(:name)
      response.headers["Cache-Control"] = "no-store"
    end

    def create
      @code = SealloConnectionCode.issue!(store: current_store, user: current_user)
      show
      render :show
    end
  end
end
