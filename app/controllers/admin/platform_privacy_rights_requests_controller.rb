# frozen_string_literal: true

module Admin
  class PlatformPrivacyRightsRequestsController < BaseController
    before_action :require_super_admin!
    before_action :set_request, only: %i[show resolve]
    skip_before_action :require_subscription_access!

    def index
      @requests = PlatformPrivacyRightsRequest.order(created_at: :desc).limit(100)
    end

    def show
    end

    def resolve
      @request.resolve!
      Platform::AdminAudit.record(
        action: "privacy_rights.resolve",
        actor: current_user,
        subject: @request,
        ip: request.remote_ip,
        privacy_request_id: @request.id,
        outcome: "ok"
      )
      redirect_to admin_platform_privacy_rights_request_path(@request), notice: t("seallo_connect_pages.privacy_rights.admin.resolved")
    end

    private

    def set_request
      @request = PlatformPrivacyRightsRequest.find(params[:id])
    end
  end
end
