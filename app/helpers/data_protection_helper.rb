# frozen_string_literal: true

module DataProtectionHelper
  TRACKING_CONSENT_COOKIE = :morea_tracking_consent

  def privacy_page_path_for_store
    return unless current_store&.pages&.published&.exists?(slug: "privacy")

    page_path("privacy")
  end

  def tracking_consent_cookie
    cookies[TRACKING_CONSENT_COOKIE].presence
  end

  def tracking_consent_granted?
    return true unless current_store&.pixels_configured?

    tracking_consent_cookie == "granted"
  end

  def tracking_consent_denied?
    tracking_consent_cookie == "denied"
  end

  def tracking_consent_pending?
    current_store&.pixels_configured? && tracking_consent_cookie.blank?
  end

  def checkout_data_protection_notice
    if current_store.cndp_authorization.present?
      t("data_protection.checkout_notice_with_cndp", number: current_store.cndp_authorization)
    else
      t("data_protection.checkout_notice")
    end
  end
end
