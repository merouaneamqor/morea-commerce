class SearchesController < ApplicationController
  SORTS = %w[featured price_asc price_desc newest].freeze
  PER_PAGE = 24
  MAX_QUERY_LENGTH = 100

  def show
    @query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "featured"
    @in_stock = params[:in_stock] == "1"
    @page = [ params[:page].to_i, 1 ].max

    products = current_store.products.active
    products = apply_query(products) if @query.present?
    products = apply_stock_filter(products) if @in_stock
    products = apply_sort(products)

    @total_count = products.except(:order).distinct.count(:id)
    @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
    @page = [ @page, @total_pages ].min
    @products = products
      .includes(:translations, :product_variants, images_attachments: :blob)
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE)
      .to_a
  end

  private

  def apply_query(products)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    locales = [ I18n.locale.to_s, Morea::Locales::DEFAULT.to_s ].uniq

    products.where(
      <<~SQL.squish,
        products.name ILIKE :pattern
        OR products.slug ILIKE :pattern
        OR EXISTS (
          SELECT 1 FROM product_translations
          WHERE product_translations.product_id = products.id
            AND product_translations.locale IN (:locales)
            AND (
              product_translations.name ILIKE :pattern
              OR product_translations.short_description ILIKE :pattern
              OR product_translations.story ILIKE :pattern
            )
        )
      SQL
      pattern: pattern,
      locales: locales
    )
  end

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

  def apply_sort(products)
    case @sort
    when "price_asc" then products.reorder(price_cents: :asc, id: :asc)
    when "price_desc" then products.reorder(price_cents: :desc, id: :asc)
    when "newest" then products.reorder(created_at: :desc, id: :desc)
    else products.reorder(featured: :desc, position: :asc, name: :asc, id: :asc)
    end
  end
end
