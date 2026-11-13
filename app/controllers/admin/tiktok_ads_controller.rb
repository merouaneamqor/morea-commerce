# frozen_string_literal: true

module Admin
  # TikTok Ads entry point on the Integrations page. The TikTok authorization itself is not built yet:
  # the button says which TikTok settings are missing, and once they are all set it says the connection
  # is not available yet, instead of pretending to connect.
  class TiktokAdsController < BaseController
    SETTINGS = %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_REDIRECT_URI].freeze

    before_action { head :not_found unless current_store }

    def connect
      missing = SETTINGS.select { |name| ENV[name].blank? }
      message = missing.any? ? t("tiktok_ads.errors.config_missing", settings: missing.join(", ")) : t("tiktok_ads.errors.not_ready")
      redirect_to "/integrations", alert: message, status: :see_other
    end
  end
end
