# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    description "Catalog for the store identified by the Bearer token."

    field :guide, String, null: false, description: "How to use this API. Read it before writing."
    field :products, [ ProductType ], null: false do
      argument :query, String, required: false
      argument :status, String, required: false
      argument :limit, Integer, required: false
    end
    field :product, ProductType, null: true do
      argument :slug, String, required: true
    end
    field :collections, [ CollectionType ], null: false do
      argument :published, Boolean, required: false
      argument :limit, Integer, required: false
    end
    field :collection, CollectionType, null: true do
      argument :slug, String, required: true
    end
    field :stats, Analytics::StoreStatsType, null: false do
      argument :since, GraphQL::Types::ISO8601Date, required: false
      argument :until, GraphQL::Types::ISO8601Date, required: false, as: :until_on
    end
    field :product_stats, [ Analytics::ProductStatType ], null: false do
      argument :since, GraphQL::Types::ISO8601Date, required: false
      argument :until, GraphQL::Types::ISO8601Date, required: false, as: :until_on
      argument :slug, String, required: false
    end
    field :orders, [ Analytics::OrderType ], null: false do
      argument :status, String, required: false
      argument :since, GraphQL::Types::ISO8601Date, required: false
      argument :until, GraphQL::Types::ISO8601Date, required: false, as: :until_on
      argument :city, String, required: false
      argument :limit, Integer, required: false
    end
    field :order, Analytics::OrderType, null: true do
      argument :number, String, required: true
    end
    field :store_settings, Storefront::SettingsType, null: false
    field :discounts, [ Storefront::DiscountType ], null: false
    field :customers, [ Storefront::CustomerType ], null: false do
      argument :query, String, required: false
      argument :limit, Integer, required: false
    end
    field :customer, Storefront::CustomerType, null: true do
      argument :phone, String, required: true
    end
    field :abandoned_carts, [ Storefront::AbandonedCartType ], null: false do
      argument :older_than_hours, Integer, required: false
      argument :limit, Integer, required: false
    end
    field :active_carts, [ Storefront::AbandonedCartType ], null: false do
      argument :within_hours, Integer, required: false
      argument :limit, Integer, required: false
    end
    field :home_sections, [ Storefront::SectionType ], null: false
    field :pages, [ Storefront::PageType ], null: false
    field :menu_items, [ Storefront::MenuItemType ], null: false
    field :section_schema, GraphQL::Types::JSON, null: false
    field :home_layout, Builders::HomeLayoutType, null: false
    field :landing_pages, [ Builders::LandingPageType ], null: false
    field :landing_page, Builders::LandingPageType, null: true do
      argument :slug, String, required: true
    end
    field :export_csv, Storefront::CsvExportType, null: false do
      argument :kind, String, required: true
    end

    field :store_profile, GraphQL::Types::JSON, null: false,
          description: "Brand guidelines, locales, pricing rules, and agent approval policies for this store."
    field :full_catalog, Autonomy::FullCatalogType, null: false do
      argument :page, Integer, required: false
      argument :per_page, Integer, required: false
      argument :status, String, required: false
    end
    field :audit_store, Autonomy::AuditReportType, null: false do
      argument :status, String, required: false
      argument :limit, Integer, required: false
    end
    field :product_schema, GraphQL::Types::JSON, null: false
    field :validate_product, Autonomy::ValidateProductResultType, null: false do
      argument :slug, String, required: true
    end
    field :suggest_collection_structure, Autonomy::CollectionSuggestionReportType, null: false do
      argument :limit, Integer, required: false
    end
    field :changeset, Autonomy::ChangesetType, null: true do
      argument :token, String, required: true
    end
    field :inventory_levels, [ Inventory::LevelType ], null: false do
      argument :slug, String, required: false
      argument :status, String, required: false
      argument :low_stock_only, Boolean, required: false
      argument :limit, Integer, required: false
    end
    field :inventory_movements, [ Inventory::MovementType ], null: false do
      argument :slug, String, required: false
      argument :reason, String, required: false
      argument :since, GraphQL::Types::ISO8601Date, required: false
      argument :until, GraphQL::Types::ISO8601Date, required: false, as: :until_on
      argument :limit, Integer, required: false
    end
    field :inventory_summary, Inventory::SummaryType, null: false do
      argument :since, GraphQL::Types::ISO8601Date, required: false
      argument :until, GraphQL::Types::ISO8601Date, required: false, as: :until_on
    end

    def guide
      CatalogGuide.text
    end

    def store_profile
      Catalog::Autonomy.profile_for(store)
    end

    def full_catalog(page: nil, per_page: nil, status: nil)
      page_number = [ page.to_i, 1 ].max
      page_number = 1 if page.to_i <= 0
      size = per_page.to_i
      size = 50 if size <= 0
      size = size.clamp(1, 100)

      scope = store.products.includes(:translations, :collections, :product_variants)
      scope = scope.where(status: status) if status.present?
      total = scope.count
      products = scope.order(:position, :name).offset((page_number - 1) * size).limit(size)
      collections = store.collections.includes(:translations, :products).order(:position, :name)

      {
        page: page_number,
        per_page: size,
        product_total: total,
        collection_total: collections.size,
        has_more_products: (page_number * size) < total,
        products: products,
        collections: collections
      }
    end

    def audit_store(status: nil, limit: nil)
      Catalog::Audit.store(store, status: status, limit: limit)
    end

    def product_schema
      Catalog::Autonomy.product_schema
    end

    def validate_product(slug:)
      Catalog::ValidateProduct.call(store, slug: slug)
    end

    def suggest_collection_structure(limit: nil)
      Catalog::SuggestCollections.call(store, limit: limit)
    end

    def changeset(token:)
      Catalog::Changesets.present(store.agent_changesets.find_by!(token: token))
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def products(query: nil, status: nil, limit: nil)
      scope = store.products.includes(:translations, :collections, :product_variants)
      scope = scope.where(status: status) if status.present?
      if query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        scope = scope.left_joins(:translations).where(
          "products.name ILIKE :term OR products.slug ILIKE :term OR product_translations.name ILIKE :term",
          term: term
        ).distinct
      end
      scope.order(:position, :name).limit(clamp_limit(limit))
    end

    def product(slug:)
      store.products.includes(:translations, :collections, :product_variants).find_by(slug: slug)
    end

    def collections(published: nil, limit: nil)
      scope = store.collections.includes(:translations, :products)
      scope = scope.where(published: published) unless published.nil?
      scope.order(:position, :name).limit(clamp_limit(limit))
    end

    def collection(slug:)
      store.collections.includes(:translations, :products).find_by(slug: slug)
    end

    def stats(since: nil, until_on: nil)
      analytics { Catalog::Analytics.store_stats(store, since: since, until_on: until_on) }
    end

    def product_stats(since: nil, until_on: nil, slug: nil)
      analytics { Catalog::Analytics.product_stats(store, since: since, until_on: until_on, slug: slug) }
    end

    def orders(status: nil, since: nil, until_on: nil, city: nil, limit: nil)
      analytics { Catalog::Analytics.orders(store, status: status, since: since, until_on: until_on, city: city, limit: limit) }
    end

    def order(number:)
      Catalog::Analytics.order(store, number)
    end

    def store_settings
      store
    end

    def discounts
      store.discounts.order(active: :desc, code: :asc)
    end

    def customers(query: nil, limit: nil)
      scope = store.customers.order(orders_count: :desc, name: :asc)
      if query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        scope = scope.where("name ILIKE :term OR phone ILIKE :term OR email ILIKE :term OR city ILIKE :term", term: term)
      end
      scope.limit(clamp_limit(limit))
    end

    def customer(phone:)
      store.customers.includes(:addresses).find_by(phone: Catalog::StoreOps.normalize_phone(phone))
    end

    def abandoned_carts(older_than_hours: nil, limit: nil)
      store_ops { Catalog::StoreOps.abandoned_carts(store, older_than_hours: older_than_hours, limit: limit) }
    end

    def active_carts(within_hours: nil, limit: nil)
      store_ops { Catalog::StoreOps.active_carts(store, within_hours: within_hours, limit: limit) }
    end

    def home_sections
      store.home_sections.ordered.includes(:translations)
    end

    def pages
      store.pages.includes(:translations).order(:slug)
    end

    def menu_items
      store.menu_items.ordered.includes(:translations)
    end

    def section_schema
      Catalog::Builders.section_schema
    end

    def home_layout
      Catalog::Builders.home_layout(store)
    end

    def landing_pages
      Catalog::Builders.landing_pages(store)
    end

    def landing_page(slug:)
      Catalog::Builders.landing_page(store, slug: slug)
    rescue Catalog::Builders::Error
      nil
    end

    def export_csv(kind:)
      store_ops { Catalog::StoreOps.export_csv(store, kind: kind) }
    end

    def inventory_levels(slug: nil, status: nil, low_stock_only: nil, limit: nil)
      inventory { Catalog::Inventory.levels(store, slug: slug, status: status, low_stock_only: low_stock_only, limit: limit) }
    end

    def inventory_movements(slug: nil, reason: nil, since: nil, until_on: nil, limit: nil)
      inventory { Catalog::Inventory.movements(store, slug: slug, reason: reason, since: since, until_on: until_on, limit: limit) }
    end

    def inventory_summary(since: nil, until_on: nil)
      inventory { Catalog::Inventory.summary(store, since: since, until_on: until_on) }
    end

    private

    def store
      context.fetch(:store)
    end

    def analytics
      yield
    rescue Catalog::Analytics::Error => e
      raise GraphQL::ExecutionError, e.message
    end

    def store_ops
      yield
    rescue Catalog::StoreOps::Error => e
      raise GraphQL::ExecutionError, e.message
    end

    def inventory
      yield
    rescue Catalog::Inventory::Error, Catalog::Analytics::Error => e
      raise GraphQL::ExecutionError, e.message
    end

    def clamp_limit(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 100)
    end
  end
end
