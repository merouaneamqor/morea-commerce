module Admin
  class ShopifyPrivacyRequestsController < BaseController
    # Privacy obligations continue after a merchant subscription expires.
    skip_before_action :require_subscription_access!
    before_action -> { head :not_found unless current_store }
    before_action :set_request, except: :index
    before_action -> { response.headers["Cache-Control"] = "no-store" }

    def index
      @requests = scoped_requests.order(created_at: :desc).limit(100)
    end

    def show; end

    def export
      send_data JSON.pretty_generate(@privacy_request.export_data), type: "application/json", disposition: "attachment", filename: "privacy-request-#{@privacy_request.id}.json"
    rescue ArgumentError
      head :unprocessable_entity
    end

    def complete
      @privacy_request.complete!
      redirect_to admin_shopify_privacy_request_path(@privacy_request), notice: t("seallo_connect.privacy.completed_notice"), status: :see_other
    rescue ArgumentError
      redirect_to admin_shopify_privacy_request_path(@privacy_request), alert: t("seallo_connect.privacy.retained_alert"), status: :see_other
    end

    def retry_processing
      ShopifyPrivacyRequestJob.perform_later(@privacy_request.id)
      redirect_to admin_shopify_privacy_request_path(@privacy_request), notice: t("seallo_connect.privacy.queued_notice"), status: :see_other
    end

    private

    def scoped_requests
      ShopifyPrivacyRequest.where(store_connection_id: current_store.store_connections.where(shopify_app: "seallo_connect").select(:id))
    end

    def set_request
      @privacy_request = scoped_requests.find(params[:id])
    end
  end
end
