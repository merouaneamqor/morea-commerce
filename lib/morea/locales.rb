# frozen_string_literal: true

module Morea
  module Locales
    AVAILABLE = %i[fr en ar].freeze
    DEFAULT = :fr
    RTL = %i[ar].freeze

    LABELS = {
      fr: "Français",
      en: "English",
      ar: "العربية"
    }.freeze

    CODES = {
      fr: "FR",
      en: "EN",
      ar: "AR"
    }.freeze

    module_function

    def available?(locale)
      AVAILABLE.map(&:to_s).include?(locale.to_s)
    end

    def rtl?(locale = I18n.locale)
      RTL.map(&:to_s).include?(locale.to_s)
    end

    def label_for(locale)
      LABELS[locale.to_sym] || locale.to_s
    end

    def code_for(locale)
      CODES[locale.to_sym] || locale.to_s.upcase
    end
  end
end
