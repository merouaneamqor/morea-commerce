# frozen_string_literal: true

module Morea
  # Default cookie policy describing necessary cookies and opt-in measurement pixels.
  module CookiePolicy
    LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze

    module_function

    def body_for(store, locale:)
      I18n.with_locale(locale) do
        I18n.t(
          "cookie_policy.body",
          store: store.data_controller_name,
          site: store.origin,
          contact: store.privacy_rights_contact_display,
          privacy_path: "/#{locale}/pages/privacy"
        )
      end
    end

    def titles
      {
        "fr" => "Politique de cookies",
        "en" => "Cookie policy",
        "ar" => "سياسة ملفات تعريف الارتباط"
      }
    end

    def menu_labels
      {
        "fr" => "Cookies",
        "en" => "Cookies",
        "ar" => "الكوكيز"
      }
    end
  end
end
