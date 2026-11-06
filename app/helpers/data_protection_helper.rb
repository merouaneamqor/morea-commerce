# frozen_string_literal: true

module DataProtectionHelper
  TRACKING_CONSENT_COOKIE = :morea_tracking_consent
  GRANTED = "granted"
  DENIED = "denied"

  def privacy_page_path_for_store
    page_path_if_published("privacy")
  end

  def terms_page_path_for_store
    page_path_if_published("terms")
  end

  def cookies_page_path_for_store
    page_path_if_published("cookies")
  end

  def page_path_if_published(slug)
    return unless current_store&.pages&.published&.exists?(slug: slug)

    page_path(slug)
  end

  def tracking_consent_value
    cookies[TRACKING_CONSENT_COOKIE].to_s
  end

  def tracking_consent_granted?
    tracking_consent_value == GRANTED
  end

  def tracking_consent_denied?
    tracking_consent_value == DENIED
  end

  def tracking_consent_decided?
    tracking_consent_granted? || tracking_consent_denied?
  end

  def cookie_notice_pending?
    current_store.present? && !tracking_consent_decided?
  end

  def checkout_rights_notice
    number = current_store&.cndp_authorization.to_s.strip
    if number.present?
      t("data_protection.checkout_notice_with_cndp", number: number)
    else
      t("data_protection.checkout_notice")
    end
  end
end
