# frozen_string_literal: true

# Shared sort + in-stock SQL for public catalog listings (collections, search).
module StorefrontCatalogFilters
  extend ActiveSupport::Concern

  SORTS = %w[featured price_asc price_desc newest].freeze

  private

  def apply_stock_filter(products)
    products.where(<<~SQL.squish)
      products.track_inventory = FALSE
      OR (
        NOT EXISTS (
          SELECT 1 FROM product_variants
          WHERE product_variants.product_id = products.id
        )
        AND products.stock > 0
      )
      OR EXISTS (
        SELECT 1 FROM product_variants
        WHERE product_variants.product_id = products.id
          AND product_variants.active = TRUE
          AND product_variants.stock > 0
      )
    SQL
  end

  def apply_catalog_sort(products, sort:, featured: false)
    case sort
    when "price_asc" then products.reorder(price_cents: :asc, id: :asc)
    when "price_desc" then products.reorder(price_cents: :desc, id: :asc)
    when "newest" then products.reorder(created_at: :desc, id: :desc)
    else
      if featured
        products.reorder(featured: :desc, position: :asc, name: :asc, id: :asc)
      else
        products.order("collection_products.position", :name)
      end
    end
  end
end
