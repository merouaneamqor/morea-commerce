# frozen_string_literal: true

module StorefrontThemes
  # Builds unsaved HomeSection records from a draft snapshot so admin preview can
  # reuse the public home/sections/* partials (images, collections, locales).
  class PreviewSections
    LOCALES = UpdateSnapshot::LOCALES

    def self.call(store:, snapshot:)
      new(store: store, snapshot: snapshot).call
    end

    def initialize(store:, snapshot:)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      @snapshot = normalize(snapshot)
    end

    def call
      sections = Array(@snapshot["sections"])
      sections.filter_map.with_index do |data, position|
        next unless data.is_a?(Hash)
        next if data["visible"] == false
        next unless SectionBlock::KINDS.key?(data["kind"].to_s)

        build_section(data, position)
      end
    end

    private

    def normalize(snapshot)
      value = snapshot.is_a?(String) ? JSON.parse(snapshot) : snapshot
      return {} unless value.is_a?(Hash)

      value.deep_stringify_keys
    rescue JSON::ParserError
      {}
    end

    def build_section(data, position)
      section = @store.home_sections.build(
        kind: data["kind"].to_s,
        position: position,
        visible: data.fetch("visible", true) != false,
        settings: normalize_settings(data["settings"], data["kind"].to_s)
      )

      translations = data["translations"]
      if translations.is_a?(Hash)
        translations.each do |locale, attributes|
          next unless LOCALES.include?(locale.to_s)
          next unless attributes.is_a?(Hash)

          allowed = SectionBlock::TEXT_FIELDS.fetch(data["kind"].to_s, []).map(&:to_s)
          section.translations.build(
            attributes.stringify_keys.slice(*allowed).merge("locale" => locale.to_s)
          )
        end
      end

      section
    end

    def normalize_settings(settings, kind)
      return {} unless settings.is_a?(Hash)

      allowed = SectionBlock::SETTING_FIELDS.fetch(kind, []).map(&:to_s)
      settings.stringify_keys.slice(*allowed)
    end
  end
end
