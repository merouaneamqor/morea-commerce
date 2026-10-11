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
end
