# frozen_string_literal: true

module Seller
  # Dashboard figures for the seller workspace: order counts and rates, and the orders waiting for work.
  # Money results (revenue, cost of goods, delivery, advertising, profit) are not computed here: they belong to
  # AccountingStats, the single source for those numbers, and are shown on the Comptabilité page.
  class DashboardStats
    # Older links used ?period=today|7d|30d; they still open the matching range.
    LEGACY_PERIODS = { "today" => "today", "7d" => "last_7", "30d" => "last_30" }.freeze

    # An order waiting for the call centre.
    AWAITING_STATUSES = %w[new].freeze
    # A parcel handed to the carrier and not yet delivered or returned (problem statuses are still in flight).
    IN_TRANSIT_STATUSES = %w[awaiting_pickup picked_up in_transit out_for_delivery address_issue unreachable postponed].freeze
    CONFIRMED_STATUSES = (Order::STATUSES - %w[new cancelled]).freeze
    SHIPPED_STATUSES = (IN_TRANSIT_STATUSES + %w[delivered returned]).freeze

    attr_reader :range

    # range: a DateRange (store days, inclusive end); the previous period is the same number of days just before.
    def initialize(store:, range: nil, period: nil, now: Time.current)
      @store = store
      today = DateRange.today(now)
      @range = range || DateRange.preset(LEGACY_PERIODS.fetch(period.to_s, "last_7"), today: today)
      @previous = @range.previous
    end

    def to_h
      created = orders.where(created_at: range.time_range)
      total = created.count
      previous_total = orders.where(created_at: @previous.time_range).count
      counts = created.group(:status).count
      confirmed = counts.slice(*CONFIRMED_STATUSES).values.sum
      shipped = counts.slice(*SHIPPED_STATUSES).values.sum
      delivered = counts.fetch("delivered", 0)
      cancelled = counts.fetch("cancelled", 0)

      delivered_in_period = delivered_orders(range).count
      refused = orders.where(status: "returned", returned_at: range.time_range).count
      awaiting = orders.where(status: AWAITING_STATUSES)
      in_transit = orders.where(status: IN_TRANSIT_STATUSES)

      {
        range: { from: range.from.iso8601, to: range.to.iso8601, days: range.days },
        currency: currency,
        pending: awaiting.count,
        money: money_figures,
        low_stock: low_stock,
        kpis: {
          orders: total,
          orders_delta: delta(total, previous_total),
          confirmed: confirmed,
          confirmation_rate: percent(confirmed, total),
          returned: counts.fetch("returned", 0),
          return_rate: percent(counts.fetch("returned", 0), shipped),
          delivered: delivered,
          delivery_rate: percent(delivered, shipped),
          awaiting: awaiting.count,
          awaiting_amount: units(awaiting.sum(:total_cents)),
          in_transit: in_transit.count,
          in_transit_amount: units(in_transit.sum(:total_cents)),
          cancelled: cancelled,
          cancel_rate: percent(cancelled, total),
          refused: refused,
          refusal_rate: percent(refused, delivered_in_period + refused)
        },
        latest: latest_orders
      }
    end

    # Orders of this workspace in its home currency (DH and MAD are the same currency).
    def orders
      @orders ||= @store.orders.active.where(currency: currency_codes)
    end

    def new_orders_count = orders.where(status: "new").count

    # Pieces left at or below which an article is flagged on the dashboard.
    LOW_STOCK_THRESHOLD = 5
    LOW_STOCK_LIST_LIMIT = 6

    # Tracked articles with LOW_STOCK_THRESHOLD pieces or fewer: a product without variants by its own stock,
    # otherwise each active variant by its own stock. Lowest first. `count` is all of them, `items` the first few.
    def low_stock
      items = @store.products.active.low_stock(LOW_STOCK_THRESHOLD).includes(:product_variants).flat_map do |product|
        variants = product.product_variants.select(&:active)
        if variants.empty?
          product.stock.to_i <= LOW_STOCK_THRESHOLD ? [ low_stock_item(product, nil, product.stock) ] : []
        else
          variants.select { |variant| variant.stock.to_i <= LOW_STOCK_THRESHOLD }.map { |variant| low_stock_item(product, variant.display_name, variant.stock) }
        end
      end.sort_by { |item| [ item[:stock], item[:name].to_s ] }
      { threshold: LOW_STOCK_THRESHOLD, count: items.size, items: items.first(LOW_STOCK_LIST_LIMIT) }
    end

    # Active products with no cost entered (a count, shown as a badge in the menu).
    def missing_costs
      @store.products.active.where(cost_cents: [ nil, 0 ]).count
    end

    private

    def low_stock_item(product, variant_name, stock)
      { id: product.id, slug: product.slug, name: product.name, variant: variant_name.presence, stock: stock.to_i }
    end

    # Revenue and average basket come from AccountingStats, the single source of money figures (delivered orders
    # of the range, compared with the previous period), so the dashboard and Comptabilité always agree.
    def money_figures
      accounting = AccountingStats.new(store: @store, range: range)
      totals = accounting.totals
      {
        revenue: units(totals.revenue),
        revenue_delta: delta(totals.revenue, accounting.previous_totals.revenue),
        delivered_orders: totals.orders,
        average_basket: totals.average_basket && (totals.average_basket / 100).round(2).to_f
      }
    end

    def currency
      code = @store.currency.to_s.upcase
      code == "DH" ? "MAD" : code
    end

    def currency_codes
      currency == "MAD" ? %w[DH MAD] : [ currency ]
    end

    def delivered_orders(period)
      orders.where(status: "delivered", delivered_at: period.time_range)
    end

    # Cents, rounded to whole units of 1/100.
    def units(cents) = (cents.to_d / 100).round(2).to_f

    def percent(numerator, denominator)
      denominator.positive? ? (numerator * 100.0 / denominator).round : nil
    end

    def delta(current, previous)
      previous.positive? ? ((current - previous) * 100.0 / previous).round : nil
    end

    def latest_orders
      orders.order(created_at: :desc, id: :desc).limit(6).map do |order|
        { id: order.id, number: order.number, customer: order.customer_name, city: order.customer_city,
          total: units(order.total_cents), status: order.status }
      end
    end
  end
end
