# frozen_string_literal: true

module Morea
  # Default storefront terms for COD merchants (editable CMS page after install).
  module TermsOfService
    LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze

    module_function

    def body_for(store, locale:)
      I18n.with_locale(locale) do
        I18n.t(
          "terms_of_service.body",
          store: store.data_controller_name,
          site: store.origin,
          contact: store.privacy_rights_contact_display,
          currency: store.currency,
          age: store.minimum_purchase_age
        )
      end
    end

    def titles
      {
        "fr" => "Conditions générales",
        "en" => "Terms of service",
        "ar" => "شروط الاستخدام"
      }
    end

    def menu_labels
      {
        "fr" => "Conditions",
        "en" => "Terms",
        "ar" => "الشروط"
      }
    end
  end
end
