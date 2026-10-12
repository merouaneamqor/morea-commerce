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

    def guide
      CatalogGuide.text
    end

    def products(query: nil, status: nil, limit: nil)
      scope = store.products.includes(:translations, :collections)
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
      store.products.includes(:translations, :collections).find_by(slug: slug)
    end

    def collections(published: nil, limit: nil)
      scope = store.collections.includes(:translations, :products)
      scope = scope.where(published: published) unless published.nil?
      scope.order(:position, :name).limit(clamp_limit(limit))
    end

    def collection(slug:)
      store.collections.includes(:translations, :products).find_by(slug: slug)
    end

    private

    def store
      context.fetch(:store)
    end

    def clamp_limit(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 100)
    end
  end
end
