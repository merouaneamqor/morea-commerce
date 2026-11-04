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
        kpis: {
          orders: total,
          orders_delta: delta(total, previous_total),
          confirmation_rate: percent(confirmed, total),
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

    # Active products with no cost entered (a count, shown as a badge in the menu).
    def missing_costs
      @store.products.active.where(cost_cents: [ nil, 0 ]).count
    end

    private

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
