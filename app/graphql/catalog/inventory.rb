# frozen_string_literal: true

module Catalog
  module Inventory
    class Error < StandardError; end

    Level = Data.define(
      :slug, :name, :status, :track_inventory, :sku, :size, :color, :variant_id,
      :stock, :sellable_stock, :low_stock, :stock_value_dh, :price_dh
    )
    Summary = Data.define(
      :tracked_products, :untracked_products, :low_stock_count, :out_of_stock_count,
      :total_units, :total_stock_value_dh, :threshold, :by_reason
    )
    ReasonCount = Data.define(:reason, :count, :quantity)

    module_function

    def levels(store, slug: nil, low_stock_only: false, status: nil, limit: nil)
      threshold = store.low_stock_threshold
      products = store.products.includes(:product_variants, :translations).order(:position, :name)
      products = products.where(slug: slug) if slug.present?
      products = products.where(status: status) if status.present?
      raise Error, "Product not found: #{slug}" if slug.present? && products.empty?

      scanned = products.limit(slug.present? ? 1 : 500).to_a
      rows = scanned.flat_map { |product| levels_for_product(product, store, threshold) }
      rows = rows.select(&:low_stock) if low_stock_only
      rows.first(clamp(limit))
    end

    def summary(store, since: nil, until_on: nil)
      threshold = store.low_stock_threshold
      products = store.products.includes(:product_variants).to_a
      tracked = products.select(&:track_inventory)
      levels = tracked.flat_map { |product| levels_for_product(product, store, threshold) }

      movements = InventoryMovement.joins(:product).where(products: { store_id: store.id })
      if since.present? || until_on.present?
        from, to = Catalog::Analytics.period(since, until_on)
        movements = movements.where(created_at: from.beginning_of_day..to.end_of_day)
      end

      by_reason = movements.group(:reason).pluck(
        Arel.sql("reason"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(quantity), 0)")
      ).map { |reason, count, quantity| ReasonCount.new(reason: reason, count: count, quantity: quantity.to_i) }

      Summary.new(
        tracked_products: tracked.size,
        untracked_products: products.size - tracked.size,
        low_stock_count: levels.count(&:low_stock),
        out_of_stock_count: levels.count { |row| row.stock.to_i <= 0 },
        total_units: levels.sum { |row| row.stock.to_i },
        total_stock_value_dh: levels.sum { |row| row.stock_value_dh.to_i },
        threshold: threshold,
        by_reason: by_reason.sort_by(&:reason)
      )
    end

    def movements(store, slug: nil, reason: nil, since: nil, until_on: nil, limit: nil)
      scope = InventoryMovement.joins(:product).where(products: { store_id: store.id })
        .includes(:product, :product_variant, :order)
        .order(created_at: :desc)

      if slug.present?
        product = store.products.find_by(slug: slug)
        raise Error, "Product not found: #{slug}" unless product

        scope = scope.where(product_id: product.id)
      end
      if reason.present?
        raise Error, "Unknown reason: #{reason}" unless ::Inventory::Adjuster::ALL_REASONS.include?(reason)

        scope = scope.where(reason: reason)
      end
      if since.present? || until_on.present?
        from, to = Catalog::Analytics.period(since, until_on)
        scope = scope.where(created_at: from.beginning_of_day..to.end_of_day)
      end

      scope.limit(clamp(limit))
    end

    def adjust!(store, slug:, quantity:, reason:, note: nil, size: nil, color: nil, variant_id: nil)
      product = store.products.includes(:product_variants).find_by(slug: slug)
      raise Error, "Product not found: #{slug}" unless product

      ::Inventory::Adjuster.adjust!(
        product: product,
        quantity: quantity,
        reason: reason,
        note: note,
        size: size,
        color: color,
        variant_id: variant_id
      )
    rescue ::Inventory::Adjuster::Error => e
      raise Error, e.message
    end

    def set!(store, slug:, stock:, reason: "correction", note: nil, size: nil, color: nil, variant_id: nil)
      product = store.products.includes(:product_variants).find_by(slug: slug)
      raise Error, "Product not found: #{slug}" unless product

      ::Inventory::Adjuster.set!(
        product: product,
        stock: stock,
        reason: reason.presence || "correction",
        note: note,
        size: size,
        color: color,
        variant_id: variant_id
      )
    rescue ::Inventory::Adjuster::Error => e
      raise Error, e.message
    end

    def levels_for_product(product, store, threshold)
      price = product.price_dh
      unless product.track_inventory
        return [
          Level.new(
            slug: product.slug,
            name: product.name,
            status: product.status,
            track_inventory: false,
            sku: product.sku,
            size: nil,
            color: nil,
            variant_id: nil,
            stock: nil,
            sellable_stock: nil,
            low_stock: false,
            stock_value_dh: nil,
            price_dh: price
          )
        ]
      end

      variants = product.product_variants.select(&:active?)
      if variants.any?
        return variants.sort_by { |variant| [ ProductVariant.size_rank(variant.size_value), variant.color_value.to_s ] }.map do |variant|
          stock = variant.stock
          Level.new(
            slug: product.slug,
            name: product.name,
            status: product.status,
            track_inventory: true,
            sku: variant.sku.presence || product.sku,
            size: variant.size_value,
            color: variant.color_value,
            variant_id: variant.id.to_s,
            stock: stock,
            sellable_stock: stock,
            low_stock: stock <= threshold,
            stock_value_dh: price * stock,
            price_dh: price
          )
        end
      end

      stock = product.stock
      [
        Level.new(
          slug: product.slug,
          name: product.name,
          status: product.status,
          track_inventory: true,
          sku: product.sku,
          size: nil,
          color: nil,
          variant_id: nil,
          stock: stock,
          sellable_stock: stock,
          low_stock: stock <= threshold,
          stock_value_dh: price * stock,
          price_dh: price
        )
      ]
    end

    def clamp(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 200)
    end

    private_class_method :levels_for_product, :clamp
  end
end
