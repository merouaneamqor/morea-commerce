# frozen_string_literal: true

module Catalog
  module Translations
    module_function

    def assign!(record, entries)
      Array(entries).each do |entry|
        attrs = entry.to_h.symbolize_keys
        locale = attrs[:locale].to_s
        next unless Morea::Locales.available?(locale)

        translation = record.translations.detect { |item| item.locale == locale } ||
          record.translations.build(locale: locale)

        attrs.except(:locale).each do |key, value|
          next if value.nil?
          next unless translation.respond_to?("#{key}=")

          translation.public_send("#{key}=", value)
        end
      end

      default_name = record.translations.detect { |item| item.locale == Morea::Locales::DEFAULT.to_s }&.name
      default_name = record.translations.map(&:name).find(&:present?) if default_name.blank?
      record.name = default_name if default_name.present? && record.name.blank?
    end
  end
end
