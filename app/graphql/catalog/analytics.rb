# frozen_string_literal: true

module Catalog
  class Analytics
    class Error < StandardError; end

    StatusCount = Data.define(:status, :count)
    CityStat = Data.define(:city, :orders, :delivered, :delivery_rate, :revenue_dh)
    DayStat = Data.define(:date, :placed, :delivered, :revenue_dh)
    StoreStats = Data.define(
      :from, :to,
      :placed_count, :placed_revenue_dh, :shipping_dh, :discount_dh, :average_order_dh,
      :delivered_count, :delivered_revenue_dh,
      :delivery_rate, :cancel_rate, :return_rate,
      :by_status, :pipeline, :by_city, :by_day
    )
    VariantStat = Data.define(:name, :units_placed, :units_delivered, :stock)
    ProductStat = Data.define(
      :slug, :name, :status, :price_dh, :stock, :stock_value_dh, :low_stock,
      :units_placed, :units_delivered, :units_cancelled, :units_returned,
      :revenue_placed_dh, :revenue_delivered_dh, :orders, :variants
    )

    def self.period(since, until_on)
      finish = coerce_date(until_on) || Date.current
      start_on = coerce_date(since) || (finish - 29)
      raise Error, "since must be on or before until" if start_on > finish
      raise Error, "Date window cannot exceed 366 days" if (finish - start_on).to_i > 365

      [ start_on, finish ]
    end

    def self.store_stats(store, since:, until_on:)
      from, to = period(since, until_on)
      range = time_range(from, to)
      placed = store.orders.where(created_at: range)
      delivered = store.orders.where(delivered_at: range)
      placed_count = placed.count
      placed_revenue = placed.sum(:total_cents)

      StoreStats.new(
        from: from,
        to: to,
        placed_count: placed_count,
        placed_revenue_dh: dh(placed_revenue),
        shipping_dh: dh(placed.sum(:shipping_cents)),
        discount_dh: dh(placed.sum(:discount_cents)),
        average_order_dh: placed_count.zero? ? 0 : dh(placed_revenue) / placed_count,
        delivered_count: delivered.count,
        delivered_revenue_dh: dh(delivered.sum(:total_cents)),
        delivery_rate: rate(placed.where(status: "delivered").count, placed_count),
        cancel_rate: rate(placed.where(status: "cancelled").count, placed_count),
        return_rate: rate(placed.where(status: "returned").count, placed_count),
        by_status: status_counts(placed),
        pipeline: status_counts(store.orders),
        by_city: city_stats(placed),
        by_day: day_stats(placed, delivered, from, to)
      )
    end

    def self.product_stats(store, since:, until_on:, slug: nil)
      from, to = period(since, until_on)
      placed_range = time_range(from, to)
      products = store.products.includes(:product_variants).order(:position, :name)
      products = products.where(slug: slug) if slug.present?
      products = products.to_a
      raise Error, "Product not found: #{slug}" if slug.present? && products.empty?

      ids = products.map(&:id)
      items = OrderItem.joins(:order).where(orders: { store_id: store.id }, product_id: ids)
      placed_items = items.where(orders: { created_at: placed_range })
      delivered_items = items.where(orders: { delivered_at: placed_range })
      cancelled_items = placed_items.where(orders: { status: "cancelled" })
      returned_items = placed_items.where(orders: { status: "returned" })

      products.map do |product|
        product_stat(
          product,
          store,
          units(placed_items, :quantity),
          units(delivered_items, :quantity),
          units(cancelled_items, :quantity),
          units(returned_items, :quantity),
          units(placed_items, :total_cents),
          units(delivered_items, :total_cents),
          order_counts(placed_items),
          variant_units(placed_items),
          variant_units(delivered_items)
        )
      end
    end

    def self.orders(store, status: nil, since: nil, until_on: nil, city: nil, limit: nil)
      scope = store.orders.includes(order_items: :product).recent
      if since.present? || until_on.present?
        from, to = period(since, until_on)
        scope = scope.where(created_at: time_range(from, to))
      end
      if status.present?
        raise Error, "Unknown status: #{status}" unless Order::STATUSES.include?(status)

        scope = scope.where(status: status)
      end
      scope = scope.where("customer_city ILIKE ?", city.to_s.strip) if city.present?
      scope.limit(clamp_limit(limit))
    end

    def self.order(store, number)
      store.orders.includes(order_items: :product).find_by(number: number.to_s.strip)
    end

    def self.dh(cents)
      cents.to_i / 100
    end

    def self.rate(part, total)
      return 0.0 if total.zero?

      (part.to_f / total * 100).round(1)
    end

    def self.coerce_date(value)
      return if value.blank?
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Error, "Invalid date: #{value}"
    end

    def self.time_range(from, to)
      from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
    end

    def self.status_counts(scope)
      counts = scope.group(:status).count
      Order::STATUSES.map { |status| StatusCount.new(status: status, count: counts[status].to_i) }
    end

    def self.city_stats(placed)
      orders = placed.group(:customer_city).count
      delivered = placed.where(status: "delivered").group(:customer_city).count
      revenue = placed.where(status: "delivered").group(:customer_city).sum(:total_cents)
      orders.map do |city, count|
        name = city.presence || "Unknown"
        delivered_count = delivered[city].to_i
        CityStat.new(
          city: name,
          orders: count,
          delivered: delivered_count,
          delivery_rate: rate(delivered_count, count),
          revenue_dh: dh(revenue[city])
        )
      end.sort_by { |row| -row.orders }
    end

    def self.day_stats(placed, delivered, from, to)
      placed_counts = count_by_day(placed, "orders.created_at")
      delivered_counts = count_by_day(delivered, "orders.delivered_at")
      revenue = sum_by_day(delivered, "orders.delivered_at", :total_cents)
      (from..to).map do |date|
        DayStat.new(
          date: date,
          placed: placed_counts[date].to_i,
          delivered: delivered_counts[date].to_i,
          revenue_dh: dh(revenue[date])
        )
      end
    end

    def self.count_by_day(scope, column)
      scope.group(day_sql(column)).count.transform_keys(&:to_date)
    end

    def self.sum_by_day(scope, column, sum_column)
      scope.group(day_sql(column)).sum(sum_column).transform_keys(&:to_date)
    end

    def self.day_sql(column)
      zone = Order.connection.quote(Time.zone.tzinfo.name)
      Arel.sql("((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{zone})::date")
    end

    def self.units(items, column)
      items.group(:product_id).sum(column)
    end

    def self.order_counts(items)
      items.group(:product_id).distinct.count(:order_id)
    end

    def self.variant_units(items)
      items.group(:product_id, :variant_name).sum(:quantity)
    end

    def self.product_stat(product, store, placed_units, delivered_units, cancelled_units, returned_units, placed_revenue, delivered_revenue, orders, placed_variants, delivered_variants)
      stock = sellable_stock(product)
      price = dh(product.price_cents)
      ProductStat.new(
        slug: product.slug,
        name: product.name,
        status: product.status,
        price_dh: price,
        stock: stock,
        stock_value_dh: stock && price * stock,
        low_stock: stock.present? && stock <= store.low_stock_threshold,
        units_placed: placed_units[product.id].to_i,
        units_delivered: delivered_units[product.id].to_i,
        units_cancelled: cancelled_units[product.id].to_i,
        units_returned: returned_units[product.id].to_i,
        revenue_placed_dh: dh(placed_revenue[product.id]),
        revenue_delivered_dh: dh(delivered_revenue[product.id]),
        orders: orders[product.id].to_i,
        variants: variant_stats(product, placed_variants, delivered_variants)
      )
    end

    def self.sellable_stock(product)
      return unless product.track_inventory

      if product.product_variants.any?
        product.product_variants.select(&:active?).sum(&:stock)
      else
        product.stock
      end
    end

    def self.variant_stats(product, placed_variants, delivered_variants)
      current = product.product_variants.sort_by { |variant| [ ProductVariant.size_rank(variant.size_value), variant.color_value.to_s ] }
      names = current.map(&:display_name)
      sold = (placed_variants.keys + delivered_variants.keys).select { |product_id, _name| product_id == product.id }.map(&:last)
      (names + sold).compact.uniq.map do |name|
        variant = current.find { |item| item.display_name == name }
        VariantStat.new(
          name: name.presence || "Default",
          units_placed: placed_variants[[ product.id, name ]].to_i,
          units_delivered: delivered_variants[[ product.id, name ]].to_i,
          stock: variant&.stock
        )
      end
    end

    def self.clamp_limit(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 100)
    end

    private_class_method :dh, :rate, :coerce_date, :time_range, :status_counts, :city_stats, :day_stats,
      :count_by_day, :sum_by_day, :day_sql, :units, :order_counts, :variant_units, :product_stat,
      :sellable_stock, :variant_stats, :clamp_limit
  end
end
