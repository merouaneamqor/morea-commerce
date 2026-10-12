# frozen_string_literal: true

module Catalog
  module Audit
    Issue = Data.define(
      :severity, :code, :entity_type, :entity_slug, :locale, :message, :suggestion, :auto_fixable, :level
    )

    SEVERITY_ORDER = { "high" => 0, "medium" => 1, "low" => 2 }.freeze

    module_function

    def store(store, status: nil, limit: nil)
      profile = Autonomy.profile_for(store)
      products = store.products.includes(:translations, :collections, :product_variants)
      products = products.where(status: status) if status.present?
      products = products.order(:position, :name).limit(clamp(limit, default: 500, max: 2000))
      collections = store.collections.includes(:translations, :products).order(:position, :name)

      issues = []
      issues.concat(product_issues(products, profile))
      issues.concat(collection_issues(collections, profile))
      issues.concat(duplicate_product_issues(products))
      issues.concat(overlapping_collection_issues(collections))

      issues = issues.sort_by { |issue| [ SEVERITY_ORDER.fetch(issue.severity, 9), issue.entity_type, issue.entity_slug.to_s ] }
      summary = {
        product_count: products.size,
        collection_count: collections.size,
        issue_count: issues.size,
        by_severity: issues.group_by(&:severity).transform_values(&:size),
        by_code: issues.group_by(&:code).transform_values(&:size),
        auto_fixable_count: issues.count(&:auto_fixable)
      }

      { summary: summary, issues: issues.map { |issue| issue_hash(issue) } }
    end

    def product_issues(products, profile)
      languages = Array(profile["languages"]).presence || Autonomy::LOCALES
      required = Array(profile["requiredProductFields"])
      required_seo = Array(profile["requiredSeoFields"])
      min_price = profile.dig("pricingRules", "minPriceDh").to_i
      threshold = profile["lowStockThreshold"].to_i

      products.flat_map do |product|
        issues = []
        fr = product.translation_for("fr")
        issues << issue("high", "missing_name", "product", product.slug, "fr",
                        "Missing French name.", "Set translations with locale fr and a name.", true, 1) if fr&.name.blank?

        languages.each do |locale|
          translation = product.translation_for(locale)
          if translation.nil? || translation.name.blank?
            issues << issue("high", "missing_translation", "product", product.slug, locale,
                            "Missing #{locale} name.", "Add a #{locale} translation name.", true, 1)
            next
          end

          required.each do |field|
            next if field == "name"
            next if translation_value(translation, field).present?

            issues << issue("medium", "missing_description", "product", product.slug, locale,
                            "Missing #{field} in #{locale}.", "Fill #{field} for locale #{locale}.", true, 1)
          end

          required_seo.each do |field|
            next if translation_value(translation, field).present?

            issues << issue("medium", "missing_seo", "product", product.slug, locale,
                            "Missing #{field} in #{locale}.", "Fill #{field} for locale #{locale}.", true, 1)
          end
        end

        unless product.images.attached?
          issues << issue("high", "missing_image", "product", product.slug, nil,
                          "Product has no images.", "Upload at least one product image.", false, 2)
        end

        if product.price_dh.to_i < min_price
          issues << issue("high", "invalid_price", "product", product.slug, nil,
                          "Price #{product.price_dh} is below the minimum #{min_price}.",
                          "Set priceDh to at least #{min_price}.", false, 2)
        end

        if product.compare_at_dh.present? && product.compare_at_dh.to_i <= product.price_dh.to_i
          issues << issue("medium", "invalid_compare_at", "product", product.slug, nil,
                          "Compare-at price must be higher than price.", "Raise compareAtDh or clear it.", true, 1)
        end

        if product.collections.empty? && product.status == "active"
          issues << issue("medium", "missing_category", "product", product.slug, nil,
                          "Active product is not in any collection.", "Assign it to an existing collection.", true, 1)
        end

        sellable = product.available_stock
        if product.track_inventory && sellable != Float::INFINITY && sellable <= threshold
          issues << issue("medium", "inventory_low", "product", product.slug, nil,
                          "Sellable stock is #{sellable} (threshold #{threshold}).",
                          "Restock variants or the product stock.", false, 2)
        end

        if product.product_variants.any?
          inactive = product.product_variants.reject(&:active)
          if inactive.any? && product.product_variants.active.sum(:stock).zero? && product.status == "active"
            issues << issue("medium", "inventory_inconsistent", "product", product.slug, nil,
                            "Active product with variants has no active sellable stock.",
                            "Activate variants or archive the product.", false, 2)
          end
        end

        issues
      end
    end

    def collection_issues(collections, profile)
      languages = Array(profile["languages"]).presence || Autonomy::LOCALES

      collections.flat_map do |collection|
        issues = []
        languages.each do |locale|
          translation = collection.translation_for(locale)
          if translation.nil? || translation.name.blank?
            issues << issue("medium", "missing_translation", "collection", collection.slug, locale,
                            "Missing #{locale} collection name.", "Add a #{locale} translation name.", true, 1)
          end
        end

        if collection.published? && collection.products.empty?
          issues << issue("low", "empty_collection", "collection", collection.slug, nil,
                          "Published collection has no products.", "Add products or unpublish it.", true, 1)
        end

        issues
      end
    end

    def duplicate_product_issues(products)
      by_name = products.group_by { |product| product.translation_for("fr")&.name.to_s.strip.downcase }
      by_name.flat_map do |name, group|
        next [] if name.blank? || group.size < 2

        group.map do |product|
          issue("medium", "duplicate_product", "product", product.slug, "fr",
                "Possible duplicate of #{group.map(&:slug).join(', ')}.",
                "Merge, archive, or differentiate the products.", false, 2)
        end
      end
    end

    def overlapping_collection_issues(collections)
      pairs = collections.combination(2).filter_map do |left, right|
        left_ids = left.products.map(&:id)
        right_ids = right.products.map(&:id)
        overlap = left_ids & right_ids
        next if overlap.empty? || left_ids.empty? || right_ids.empty?

        ratio = overlap.size.to_f / [ left_ids.size, right_ids.size ].min
        next if ratio < 0.8

        issue("low", "overlapping_collections", "collection", left.slug, nil,
              "Collection overlaps heavily with #{right.slug} (#{overlap.size} shared products).",
              "Merge collections or clarify their purpose.", false, 2)
      end
      pairs || []
    end

    def issue(severity, code, entity_type, entity_slug, locale, message, suggestion, auto_fixable, level)
      Issue.new(severity, code, entity_type, entity_slug, locale, message, suggestion, auto_fixable, level)
    end

    def issue_hash(issue)
      {
        severity: issue.severity,
        code: issue.code,
        entity_type: issue.entity_type,
        entity_slug: issue.entity_slug,
        locale: issue.locale,
        message: issue.message,
        suggestion: issue.suggestion,
        auto_fixable: issue.auto_fixable,
        level: issue.level
      }
    end

    def translation_value(translation, field)
      key = field.to_s.underscore
      return unless translation.respond_to?(key)

      translation.public_send(key).to_s.strip.presence
    end

    def clamp(limit, default:, max:)
      value = limit.to_i
      value = default if value <= 0
      value.clamp(1, max)
    end
  end
end
