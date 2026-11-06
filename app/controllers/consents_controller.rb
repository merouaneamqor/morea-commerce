# frozen_string_literal: true

class ConsentsController < ApplicationController
  def tracking
    choice = params[:choice].to_s
    unless [ DataProtectionHelper::GRANTED, DataProtectionHelper::DENIED ].include?(choice)
      return head :unprocessable_entity
    end

    cookies[DataProtectionHelper::TRACKING_CONSENT_COOKIE] = {
      value: choice,
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
