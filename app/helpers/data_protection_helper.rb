# frozen_string_literal: true

module DataProtectionHelper
  COOKIE_NOTICE_COOKIE = :morea_cookie_notice

  def privacy_page_path_for_store
    return unless current_store&.pages&.published&.exists?(slug: "privacy")

    page_path("privacy")
  end

  def cookie_notice_seen?
    cookies[COOKIE_NOTICE_COOKIE].present?
  end

  def cookie_notice_pending?
    !cookie_notice_seen?
  end

  def checkout_data_protection_notice
    if current_store.cndp_authorization.present?
      t("data_protection.checkout_notice_with_cndp", number: current_store.cndp_authorization)
    else
      t("data_protection.checkout_notice")
    end
  end
end
