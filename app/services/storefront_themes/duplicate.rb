# frozen_string_literal: true

module StorefrontThemes
  class Duplicate
    class StoreMismatch < ArgumentError; end

    def self.call(store:, theme:)
      new(store: store, theme: theme).call
    end

    def initialize(store:, theme:)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?
      raise ArgumentError, "A persisted theme is required" unless theme.is_a?(StorefrontTheme) && theme.persisted?
      raise StoreMismatch, "Theme does not belong to workspace" unless theme.store_id == store.id

      @store = store
      @theme = theme
    end

    def call
      snapshot = deep_copy_snapshot(@theme.snapshot)

      @store.storefront_themes.create!(
        name: unique_name(@theme.name),
        catalog_key: @theme.catalog_key.to_s.presence || "custom",
        status: "draft",
        snapshot: snapshot
      )
    end

    private

    def deep_copy_snapshot(snapshot)
      value = snapshot.is_a?(Hash) ? snapshot.deep_dup.deep_stringify_keys : { "sections" => [] }
      value["sections"] = Array(value["sections"]).map { |section| section.is_a?(Hash) ? section.deep_dup : section }
      value
    end

    def unique_name(base)
      base = base.to_s.strip.presence || "Theme"
      candidate = "#{base} (copy)"
      existing = @store.storefront_themes.pluck(:name)
      return candidate unless existing.include?(candidate)

      index = 2
      loop do
        candidate = "#{base} (copy #{index})"
        return candidate unless existing.include?(candidate)

        index += 1
      end
    end
  end
end
