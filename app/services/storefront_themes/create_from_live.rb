# frozen_string_literal: true

module StorefrontThemes
  # Snapshots the workspace's current home page sections into a new draft theme.
  class CreateFromLive
    CATALOG_KEY = "from_live"
    DEFAULT_NAME = "Current home page"

    def self.call(store:, name: nil)
      new(store: store, name: name).call
    end

    def initialize(store:, name: nil)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      @name = name
    end

    def call
      sections = source_sections
      snapshot = {
        "sections" => sections.each_with_index.map { |section, position| serialize_section(section, position) }
      }

      @store.storefront_themes.create!(
        name: unique_name(@name.presence || DEFAULT_NAME),
        catalog_key: CATALOG_KEY,
        status: "draft",
        snapshot: snapshot
      )
    end

    private

    def source_sections
      if @store.home_sections.exists?
        @store.home_sections.ordered.includes(:translations, image_attachment: :blob).to_a
      else
        OnlineStoreDefaults.new(@store).home_sections
      end
    end

    def serialize_section(section, position)
      kind = section.kind.to_s
      {
        "kind" => kind,
        "position" => position,
        "visible" => section.visible != false,
        "settings" => serialize_settings(section, kind),
        "translations" => serialize_translations(section, kind)
      }
    end

    def serialize_settings(section, kind)
      allowed = SectionBlock::SETTING_FIELDS.fetch(kind, []).map(&:to_s)
      settings = {}

      allowed.each do |key|
        value = section.public_send(key) if section.respond_to?(key)
        settings[key] = value.to_s if value.present?
      end

      if allowed.include?("image_url")
        src = section.respond_to?(:image_src) ? section.image_src : nil
        settings["image_url"] = src.to_s if src.present?
      end

      settings
    end

    def serialize_translations(section, kind)
      allowed = SectionBlock::TEXT_FIELDS.fetch(kind, []).map(&:to_s)
      locales = section.translations.map { |translation| translation.locale.to_s }.uniq
      locales = UpdateSnapshot::LOCALES if locales.empty?

      locales.each_with_object({}) do |locale, hash|
        translation = section.translations.detect { |row| row.locale.to_s == locale }
        next unless translation

        fields = allowed.each_with_object({}) do |field, copy|
          value = translation.public_send(field) if translation.respond_to?(field)
          copy[field] = value.to_s if value.present?
        end
        hash[locale] = fields if fields.any?
      end
    end

    def unique_name(base)
      base = base.to_s.strip.presence || DEFAULT_NAME
      existing = @store.storefront_themes.pluck(:name)
      return base unless existing.include?(base)

      index = 2
      loop do
        candidate = "#{base} (#{index})"
        return candidate unless existing.include?(candidate)

        index += 1
      end
    end
  end
end
