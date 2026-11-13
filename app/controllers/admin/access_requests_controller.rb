# frozen_string_literal: true

module Admin
  # Platform admins review requests for merchant workspace access.
  class AccessRequestsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_request, only: %i[approve reject]

    def index
      @status = AccessRequest::STATUSES.include?(params[:status]) ? params[:status] : "pending"
      @requests = AccessRequest.where(status: @status).includes(:store).order(created_at: :desc).limit(200)
      @counts = AccessRequest.group(:status).count
    end

    # Review opens provisioning; saving the workspace makes the final decision.
    def approve
      return redirect_to(admin_access_requests_path, alert: t("platform_admin.request_already_reviewed")) unless @access_request.pending?

      Platform::AdminAudit.record(
        action: "access_request.approve",
        actor: current_user,
        subject: @access_request,
        ip: request.remote_ip,
        outcome: "ok"
      )
      redirect_to new_admin_tenant_path(access_request_id: @access_request.id)
    end

    def reject
      rejected = @access_request.with_lock do
        if @access_request.pending?
          @access_request.reject!(reviewer: current_user)
          true
        end
      end
      if rejected
        Platform::AdminAudit.record(
          action: "access_request.reject",
          actor: current_user,
          subject: @access_request,
          ip: request.remote_ip,
          outcome: "ok"
        )
        redirect_to admin_access_requests_path, notice: t("platform_admin.request_rejected")
      else
        redirect_to admin_access_requests_path, alert: t("platform_admin.request_already_reviewed")
      end
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_request
      @access_request = AccessRequest.find(params[:id])
    end
  end
end
