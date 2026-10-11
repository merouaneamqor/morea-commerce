# frozen_string_literal: true

class ConsentsController < ApplicationController
  def tracking
    status = params[:status].to_s == "deny" ? "denied" : "granted"
    cookies[DataProtectionHelper::TRACKING_CONSENT_COOKIE] = {
      value: status,
      expires: 1.year.from_now,
      same_site: :lax,
      secure: !Rails.env.local?,
      httponly: false
    }

    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_back fallback_location: localized_root_path, allow_other_host: false }
    end
  end
end
