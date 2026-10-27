# frozen_string_literal: true

module StorefrontThemes
  class Install
    def self.call(store:, catalog_key:)
      new(store: store, catalog_key: catalog_key).call
    end

    def initialize(store:, catalog_key:)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      @catalog_key = catalog_key.to_s
    end

    def call
      definition = Catalog.fetch(@catalog_key)
      @store.storefront_themes.create!(
        name: definition.fetch("name"),
        catalog_key: @catalog_key,
        status: "draft",
        snapshot: definition
      )
    end
  end
end
