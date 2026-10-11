# frozen_string_literal: true

module Morea
  # Default privacy-policy copy aligned with CNDP website guidance (Loi 09-08).
  module PrivacyPolicy
    LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze

    module_function

    def body_for(store, locale:)
      I18n.with_locale(locale) do
        I18n.t(
          "privacy_policy.body",
          controller: store.data_controller_name,
          site: store.origin,
          contact: store.privacy_rights_contact_display,
          cndp_clause: cndp_clause(store),
          recipients: recipients_for(store, locale),
          purposes: I18n.t("privacy_policy.purposes"),
          cookies: I18n.t("privacy_policy.cookies_section"),
          retention: I18n.t("privacy_policy.retention"),
          prospecting: I18n.t("privacy_policy.prospecting")
        )
      end
    end

    def titles
      {
        "fr" => "Protection des données personnelles",
        "en" => "Personal data protection",
        "ar" => "حماية المعطيات الشخصية"
      }
    end

    def menu_labels
      {
        "fr" => "Données personnelles",
        "en" => "Privacy",
        "ar" => "الخصوصية"
      }
    end

    def cndp_clause(store)
      number = store.cndp_authorization.to_s.strip
      if number.present?
        I18n.t("privacy_policy.cndp_authorized", number: number)
      else
        I18n.t("privacy_policy.cndp_pending")
      end
    end

    def recipients_for(store, locale)
      I18n.with_locale(locale) do
        keys = %w[store_staff]
        keys << "sendit" if store.sendit_configured?
        keys << "hosting" if foreign_hosting?
        keys.map { |k| I18n.t("privacy_policy.recipients.#{k}") }.join("\n")
      end
    end

    def foreign_hosting?
      !Rails.env.local?
    end
  end
end
