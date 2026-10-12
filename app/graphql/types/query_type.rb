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

    def guide
      CatalogGuide.text
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

    private

    def store
      context.fetch(:store)
    end

    def analytics
      yield
    rescue Catalog::Analytics::Error => e
      raise GraphQL::ExecutionError, e.message
    end

    def clamp_limit(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 100)
    end
  end
end
