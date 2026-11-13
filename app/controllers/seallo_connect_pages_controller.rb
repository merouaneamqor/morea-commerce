# frozen_string_literal: true

# Public Seallo Connect pages on the platform apex (overview and support, pricing, privacy policy, terms).
# The Shopify app listing links here. Contact details come from the environment so no address is
# invented in source; when none is configured the pages simply omit the email line.
class SealloConnectPagesController < ApplicationController
  layout "bare"

  helper_method :support_email, :legal_entity_name, :legal_registration_number, :legal_address

  def show; end

  def pricing; end

  def privacy; end

  def terms; end

  def cookie_policy; end

  def refunds; end

  def privacy_rights
    @privacy_rights_request = PlatformPrivacyRightsRequest.new(
      request_type: params[:type].presence_in(PlatformPrivacyRightsRequest::TYPES) || "access"
    )
  end

  def create_privacy_rights
    @privacy_rights_request = PlatformPrivacyRightsRequest.new(privacy_rights_params)
    if @privacy_rights_request.save
      redirect_to seallo_connect_privacy_rights_path(locale: I18n.locale), notice: t("seallo_connect_pages.privacy_rights.submitted")
    else
      render :privacy_rights, status: :unprocessable_entity
    end
  end

  private

  def privacy_rights_params
    params.require(:platform_privacy_rights_request).permit(
      :request_type, :requester_name, :requester_contact, :details, :shop_domain
    )
  end

  def support_email
    email = ENV["SEALLO_SUPPORT_EMAIL"].to_s.strip
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def legal_entity_name
    ENV["SEALLO_LEGAL_ENTITY"].to_s.strip.presence
  end

  def legal_registration_number
    ENV["SEALLO_LEGAL_REGISTRATION"].to_s.strip.presence
  end

  def legal_address
    ENV["SEALLO_LEGAL_ADDRESS"].to_s.strip.presence
  end
end
