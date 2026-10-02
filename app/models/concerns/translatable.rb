# frozen_string_literal: true

module Translatable
  extend ActiveSupport::Concern

  class_methods do
    def translates(*attrs)
      class_attribute :translated_attribute_names, instance_writer: false
      self.translated_attribute_names = attrs.map(&:to_sym).freeze

      attrs.each do |attr|
        define_method(attr) do
          translated_value(attr)
        end

        define_method("#{attr}=") do |value|
          write_attribute(attr, value) if has_attribute?(attr)
          translation_for_writing(Morea::Locales::DEFAULT).public_send("#{attr}=", value)
        end
      end
    end
  end

  included do
    before_validation :sync_default_translation_to_columns
  end

  def translation_for(locale)
    locale = locale.to_s
    translations.detect { |t| t.locale == locale } ||
      (persisted? ? translations.find_by(locale: locale) : nil)
  end

  def locale_complete?(locale)
    t = translation_for(locale)
    return false if t.nil?

    primary = translated_attribute_names.first
    t.public_send(primary).to_s.strip.present?
  end

  def translation_missing?(locale)
    !locale_complete?(locale)
  end

  def available_translation_locales
    Morea::Locales::AVAILABLE.map(&:to_s).select { |locale| locale_complete?(locale) }
  end

  def build_missing_translations!
    # Checks loaded/built translations too: find_or_initialize_by only queries the DB,
    # so calling this twice on a new record used to build every locale twice
    Morea::Locales::AVAILABLE.map(&:to_s).each do |locale|
      translations.build(locale: locale) unless translations.any? { |t| t.locale == locale }
    end
    self
  end

  private

  def translated_value(attr)
    locales_to_try = [I18n.locale.to_s, Morea::Locales::DEFAULT.to_s].uniq
    locales_to_try.each do |locale|
      value = translation_for(locale)&.public_send(attr)
      return value if value.present?
    end

    translations.each do |translation|
      value = translation.public_send(attr)
      return value if value.present?
    end

    has_attribute?(attr) ? read_attribute(attr) : nil
  end

  def translation_for_writing(locale)
    locale = locale.to_s
    translations.detect { |t| t.locale == locale } || translations.build(locale: locale)
  end

  def sync_default_translation_to_columns
    default = translation_for(Morea::Locales::DEFAULT)
    return unless default

    translated_attribute_names.each do |attr|
      next unless has_attribute?(attr)

      value = default.public_send(attr)
      next if value.blank?

      write_attribute(attr, value)
    end
  end
end
