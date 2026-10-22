# frozen_string_literal: true

module Catalog
  module SuggestCollections
    module_function

    def call(store, limit: nil)
      products = store.products.includes(:translations, :collections).order(:position, :name)
      collections = store.collections.includes(:translations, :products).order(:position, :name)
      max = clamp(limit, default: 20, max: 50)

      uncategorized = products.select { |product| product.collections.empty? }
      buckets = Hash.new { |hash, key| hash[key] = [] }

      products.each do |product|
        key = bucket_key(product)
        buckets[key] << product.slug if key.present?
      end

      existing_slugs = collections.map(&:slug)
      suggestions = []

      buckets.sort_by { |_key, slugs| -slugs.size }.first(max).each do |key, slugs|
        next if slugs.size < 2

        slug = key.parameterize
        next if slug.blank?
        next if existing_slugs.include?(slug)

        suggestions << {
          "action" => "create_collection",
          "slug" => slug,
          "reason" => "Group #{slugs.size} related products by shared attribute.",
          "translations" => [
            { "locale" => "fr", "name" => key.capitalize },
            { "locale" => "en", "name" => key.capitalize }
          ],
          "productSlugs" => slugs.first(40),
          "level" => 2
        }
      end

      if uncategorized.any? && collections.any?
        target = collections.max_by { |collection| collection.products.size } || collections.first
        suggestions << {
          "action" => "assign_uncategorized",
          "slug" => target.slug,
          "reason" => "Assign products with no collection to the largest existing collection.",
          "productSlugs" => uncategorized.map(&:slug).first(40),
          "level" => 1
        }
      end

      collections.to_a.combination(2).each do |left, right|
        left_ids = left.products.map(&:id)
        right_ids = right.products.map(&:id)
        overlap = left_ids & right_ids
        next if overlap.empty? || [ left_ids.size, right_ids.size ].min.zero?

        ratio = overlap.size.to_f / [ left_ids.size, right_ids.size ].min
        next if ratio < 0.8

        keep, drop = left.products.size >= right.products.size ? [ left, right ] : [ right, left ]
        suggestions << {
          "action" => "merge_collections",
          "keepSlug" => keep.slug,
          "dropSlug" => drop.slug,
          "reason" => "Collections share #{overlap.size} products (#{(ratio * 100).round}% overlap).",
          "productSlugs" => (keep.products.map(&:slug) + drop.products.map(&:slug)).uniq,
          "level" => 2
        }
      end

      selected = suggestions.first(max)
      {
        summary: {
          "productCount" => products.size,
          "collectionCount" => collections.size,
          "uncategorizedCount" => uncategorized.size,
          "suggestionCount" => selected.size
        },
        suggestions: selected.map { |row| suggestion_hash(row) }
      }
    end

    def suggestion_hash(row)
      {
        action: row["action"],
        slug: row["slug"],
        keep_slug: row["keepSlug"],
        drop_slug: row["dropSlug"],
        reason: row["reason"],
        translations: row["translations"],
        product_slugs: row["productSlugs"],
        level: row["level"]
      }
    end

    def bucket_key(product)
      translation = product.translation_for("fr") || product.translations.first
      return if translation.nil?

      material = translation.material.to_s.strip.downcase.presence
      return material if material.present?

      name = translation.name.to_s.downcase
      %w[robe hijab set blouse tunique pant jogging skirt dress].each do |token|
        return token if name.include?(token)
      end

      nil
    end

    def clamp(limit, default:, max:)
      value = limit.to_i
      value = default if value <= 0
      value.clamp(1, max)
    end
  end
end
