# frozen_string_literal: true

class PrivacyRightsController < ApplicationController
  before_action :require_store!
  before_action :require_storefront!

  def show
    @request = PrivacyRightsRequest.new(request_type: params[:type].presence_in(PrivacyRightsRequest::TYPES) || "access")
  end

  def create
    @request = current_store.privacy_rights_requests.new(request_params)
    if @request.save
      redirect_to privacy_rights_path, notice: t("privacy_rights.submitted")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def request_params
    params.require(:privacy_rights_request).permit(:request_type, :requester_name, :requester_contact, :details, :order_number)
  end

  def require_storefront!
    return if current_store.storefront_enabled?

    head :not_found
  end
end
