# frozen_string_literal: true

# Landing page for the platform apex (e.g. ollazen.com). Storefronts live on tenant subdomains.
class PlatformHomeController < ApplicationController
  layout "bare"

  def show
    case PlatformSetting.current.home_page
    when "maintenance"
      response.headers["Cache-Control"] = "private, no-store"
      response.set_header("Retry-After", "3600")
      render :maintenance, status: :service_unavailable
    when "coming_soon"
      response.headers["Cache-Control"] = "private, no-store"
      render :coming_soon
    end
  end
end

