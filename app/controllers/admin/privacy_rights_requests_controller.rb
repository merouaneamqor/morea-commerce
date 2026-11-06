# frozen_string_literal: true

module Admin
  class PrivacyRightsRequestsController < BaseController
    before_action :require_store!
    before_action :set_request, only: %i[show resolve]

    def index
      @requests = current_store.privacy_rights_requests.order(created_at: :desc).limit(100)
    end

    def show
    end

    def resolve
      @request.resolve!
      redirect_to admin_privacy_rights_request_path(@request), notice: t("privacy_rights.admin.resolved")
    end

    private

    def set_request
      @request = current_store.privacy_rights_requests.find(params[:id])
    end
  end
end
