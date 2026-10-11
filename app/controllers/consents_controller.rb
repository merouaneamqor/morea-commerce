# frozen_string_literal: true

class ConsentsController < ApplicationController
  def tracking
    cookies[DataProtectionHelper::COOKIE_NOTICE_COOKIE] = {
      value: "1",
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
