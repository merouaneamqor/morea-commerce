# frozen_string_literal: true

module StorefrontThemes
  class Publish
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
      StorefrontTheme.transaction do
        @store.lock!
        @theme.lock!
        raise StoreMismatch, "Theme does not belong to workspace" unless @theme.store_id == @store.id

        sections = @theme.snapshot.fetch("sections")
        replacements = sections.each_with_index.map { |section, position| build_section(section, position) }

        @store.home_sections.destroy_all
        replacements.each(&:save!)
        @store.storefront_themes.published.where.not(id: @theme.id)
          .update_all(status: "draft", published_at: nil, updated_at: Time.current)
        @theme.update!(status: "published", published_at: Time.current)
        @theme
      end
    end

    private

    def build_section(data, position)
      section = @store.home_sections.build(
        kind: data.fetch("kind"),
        position: position,
        visible: data.fetch("visible", true),
        settings: data.fetch("settings", {}).deep_dup
      )
      data.fetch("translations").each do |locale, attributes|
        section.translations.build(attributes.slice("heading", "subheading", "body", "button_label").merge("locale" => locale))
      end
      section
    end
  end
end
