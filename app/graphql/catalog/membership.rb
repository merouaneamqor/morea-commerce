# frozen_string_literal: true

module Catalog
  module Membership
    module_function

    def product_ids_for(store, slugs)
      ids_for(store.products, slugs)
    end

    def collection_ids_for(store, slugs)
      ids_for(store.collections, slugs)
    end

    def ids_for(scope, slugs)
      ordered = Array(slugs).map { |slug| slug.to_s.strip }.uniq
      found = scope.where(slug: ordered).index_by(&:slug)
      missing = ordered - found.keys
      ids = ordered.filter_map { |slug| found[slug]&.id }
      [ ids, missing ]
    end

    def apply_products!(collection, product_ids)
      collection.product_ids = product_ids
      product_ids.each_with_index do |product_id, index|
        collection.collection_products.find_by(product_id: product_id)&.update!(position: index)
      end
    end

    def apply_collections!(product, collection_ids)
      product.collection_ids = collection_ids
    end
  end
end
