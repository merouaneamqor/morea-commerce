# frozen_string_literal: true

module Orders
  # Product picker of the order form. Matching ignores case and accents and looks at the
  # product name, SKU and slug and at each variant's name and SKU, so "tracksu", "TRACK"
  # and "trácksuit" all find "Tracksuit". An empty query returns the first products so
  # the picker is useful before anything is typed. Every query is scoped to the store.
  class ProductSearch
    EMPTY_QUERY_LIMIT = 10
    LIMIT = 25

    def initialize(store:, query:)
      @store = store
      @query = self.class.fold(query)
    end

    # Lower-case, accent-free, single-spaced text used on both sides of the comparison.
    def self.fold(text)
      I18n.transliterate(text.to_s.unicode_normalize(:nfkc)).downcase.squish
    end

    def products
      scope = @store.products.active.includes(:product_variants).order(:name, :id)
      return scope.limit(EMPTY_QUERY_LIMIT).to_a if @query.blank?

      terms = @query.split
      scope.select { |product| terms.all? { |term| haystack(product).include?(term) } }.first(LIMIT)
    end

    private

    def haystack(product)
      variants = product.product_variants.select(&:active)
      self.class.fold([ product.name, product.sku, product.slug, *variants.flat_map { |v| [ v.name, v.sku ] } ].compact.join(" "))
    end
  end
end
