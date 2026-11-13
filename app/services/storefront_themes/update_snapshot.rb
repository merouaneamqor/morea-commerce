# frozen_string_literal: true

require "json"

module StorefrontThemes
  class UpdateSnapshot
    MAX_SECTIONS = 50
    MAX_SETTING_LENGTH = 2_048
    MAX_TEXT_LENGTH = 20_000
    LOCALES = %w[fr en ar].freeze

    class StoreMismatch < ArgumentError; end
    class PublishedTheme < ArgumentError; end
    class InvalidSnapshot < ArgumentError; end

    def self.call(store:, theme:, snapshot:)
      new(store: store, theme: theme, snapshot: snapshot).call
    end

    def initialize(store:, theme:, snapshot:)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?
      raise ArgumentError, "A persisted theme is required" unless theme.is_a?(StorefrontTheme) && theme.persisted?
      raise StoreMismatch, "Theme does not belong to workspace" unless theme.store_id == store.id
      raise PublishedTheme, "Only draft themes can be edited" unless theme.draft?

      @store = store
      @theme = theme
      @snapshot = normalize_input(snapshot)
    end

    def call
      normalized = normalize_snapshot(@snapshot)

      StorefrontTheme.transaction do
        @theme.lock!
        raise StoreMismatch, "Theme does not belong to workspace" unless @theme.store_id == @store.id
        raise PublishedTheme, "Only draft themes can be edited" unless @theme.draft?

        @theme.update!(snapshot: normalized)
        @theme
      end
    end

    private

    def normalize_input(snapshot)
      value = snapshot.is_a?(String) ? JSON.parse(snapshot) : snapshot
      raise InvalidSnapshot, "Snapshot must be a JSON object" unless value.is_a?(Hash)

      value.deep_stringify_keys
    rescue JSON::ParserError
      raise InvalidSnapshot, "Snapshot must be valid JSON"
    end

    def normalize_snapshot(snapshot)
      sections = snapshot["sections"]
      raise InvalidSnapshot, "Snapshot must contain a sections array" unless sections.is_a?(Array)
      raise InvalidSnapshot, "Snapshot cannot contain more than #{MAX_SECTIONS} sections" if sections.length > MAX_SECTIONS

      snapshot.merge("sections" => sections.each_with_index.map { |section, position| normalize_section(section, position) })
    end

    def normalize_section(section, position)
      invalid!(position, "must be an object") unless section.is_a?(Hash)
      section = section.deep_stringify_keys
      kind = section["kind"]
      invalid!(position, "has an unsupported kind") unless SectionBlock::KINDS.key?(kind)
      invalid!(position, "visible must be boolean") unless [ true, false ].include?(section["visible"])

      {
        "kind" => kind,
        "position" => position,
        "visible" => section["visible"],
        "settings" => normalize_settings(section["settings"], kind, position),
        "translations" => normalize_translations(section["translations"], kind, position)
      }
    end

    def normalize_settings(settings, kind, position)
      invalid!(position, "settings must be an object") unless settings.is_a?(Hash)
      settings = settings.deep_stringify_keys
      allowed = SectionBlock::SETTING_FIELDS.fetch(kind).map(&:to_s)
      unknown = settings.keys - allowed
      invalid!(position, "contains unsupported settings: #{unknown.join(', ')}") if unknown.any?

      settings.each_with_object({}) do |(key, value), normalized|
        validate_scalar!(value, MAX_SETTING_LENGTH, position, "setting #{key}")
        normalized[key] = value
      end
    end

    def normalize_translations(translations, kind, position)
      invalid!(position, "translations must be an object") unless translations.is_a?(Hash)
      translations = translations.deep_stringify_keys
      unknown_locales = translations.keys - LOCALES
      invalid!(position, "contains unsupported locales: #{unknown_locales.join(', ')}") if unknown_locales.any?

      allowed = SectionBlock::TEXT_FIELDS.fetch(kind).map(&:to_s)
      translations.each_with_object({}) do |(locale, fields), normalized|
        invalid!(position, "translation #{locale} must be an object") unless fields.is_a?(Hash)
        fields = fields.deep_stringify_keys
        unknown = fields.keys - allowed
        invalid!(position, "translation #{locale} contains unsupported fields: #{unknown.join(', ')}") if unknown.any?

        normalized[locale] = fields.each_with_object({}) do |(key, value), copy|
          validate_scalar!(value, MAX_TEXT_LENGTH, position, "translation #{locale}.#{key}")
          copy[key] = value
        end
      end
    end

    def validate_scalar!(value, max_length, position, label)
      invalid!(position, "#{label} must be a scalar") unless value.nil? || value.is_a?(String) || value.is_a?(Numeric)
      invalid!(position, "#{label} is too long") if value.to_s.length > max_length
    end

    def invalid!(position, message)
      raise InvalidSnapshot, "Section #{position + 1} #{message}"
    end
  end
end
