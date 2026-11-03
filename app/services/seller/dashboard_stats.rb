# frozen_string_literal: true

module Seller
  # Dashboard figures for the seller workspace, computed from orders, items, carrier fees,
  # advertising spend and agent pay. Amounts are returned in whole currency units.
  #
  #   net profit = delivered sales - cost of goods - delivery fees - advertising - agent pay
  #
  # Every formula is documented in the pull request that introduced this class.
  class DashboardStats
    PERIODS = %w[today 7d 30d].freeze
    ZONE = "Africa/Casablanca"
    DAYS = { "today" => 1, "7d" => 7, "30d" => 30 }.freeze

    # An order waiting for the call centre.
    AWAITING_STATUSES = %w[new].freeze
    # A parcel handed to the carrier and not yet delivered or returned (problem statuses are still in flight).
    IN_TRANSIT_STATUSES = %w[awaiting_pickup picked_up in_transit out_for_delivery address_issue unreachable postponed].freeze
    CONFIRMED_STATUSES = (Order::STATUSES - %w[new cancelled]).freeze
    SHIPPED_STATUSES = (IN_TRANSIT_STATUSES + %w[delivered returned]).freeze

    attr_reader :period, :from, :to

    def initialize(store:, period: "7d", now: Time.current)
      @store = store
      @period = PERIODS.include?(period.to_s) ? period.to_s : "7d"
      days = DAYS.fetch(@period)
      @to = now.in_time_zone(ZONE).end_of_day
      @from = (@to.beginning_of_day - (days - 1).days)
      @previous_to = @from - 1.second
      @previous_from = @from - days.days
    end

    def to_h
      created = orders.where(created_at: from..to)
      total = created.count
      previous_total = orders.where(created_at: @previous_from..@previous_to).count
      counts = created.group(:status).count
      confirmed = counts.slice(*CONFIRMED_STATUSES).values.sum
      shipped = counts.slice(*SHIPPED_STATUSES).values.sum
      delivered = counts.fetch("delivered", 0)
      cancelled = counts.fetch("cancelled", 0)

      figures = profit(from, to)
      previous_revenue = delivered_orders(@previous_from, @previous_to).sum(:total_cents)
      delivered_in_period = delivered_orders(from, to).count
      refused = orders.where(status: "returned", returned_at: from..to).count
      awaiting = orders.where(status: AWAITING_STATUSES)
      in_transit = orders.where(status: IN_TRANSIT_STATUSES)

      {
        period: period,
        currency: currency,
        pending: awaiting.count,
        kpis: {
          orders: total,
          orders_delta: delta(total, previous_total),
          confirmation_rate: percent(confirmed, total),
          delivered: delivered,
          delivery_rate: percent(delivered, shipped),
          net_profit: units(figures[:net]),
          revenue: units(figures[:revenue]),
          revenue_delta: delta(figures[:revenue], previous_revenue),
          average_order: delivered_in_period.positive? ? units(figures[:revenue].fdiv(delivered_in_period)) : nil,
          awaiting: awaiting.count,
          awaiting_amount: units(awaiting.sum(:total_cents)),
          in_transit: in_transit.count,
          in_transit_amount: units(in_transit.sum(:total_cents)),
          cancelled: cancelled,
          cancel_rate: percent(cancelled, total),
          refused: refused,
          refusal_rate: percent(refused, delivered_in_period + refused)
        },
        profit: figures.transform_values { |cents| units(cents) },
        series: series,
        products: profit_by_product,
        latest: latest_orders,
        missing_costs: missing_costs
      }
    end

    # Orders of this workspace in its home currency (DH and MAD are the same currency).
    def orders
      @orders ||= @store.orders.active.where(currency: currency_codes)
    end

    def new_orders_count = orders.where(status: "new").count

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

    def delivered_orders(start, finish)
      orders.where(status: "delivered", delivered_at: start..finish)
    end

    # Cents, rounded to whole units of 1/100.
    def units(cents) = (cents.to_d / 100).round(2).to_f

    def percent(numerator, denominator)
      denominator.positive? ? (numerator * 100.0 / denominator).round : nil
    end

    def delta(current, previous)
      previous.positive? ? ((current - previous) * 100.0 / previous).round : nil
    end

    def profit(start, finish)
      delivered = delivered_orders(start, finish)
      revenue = delivered.sum(:total_cents)
      goods = OrderItem.where(order_id: delivered.select(:id)).sum(Arel.sql("quantity * COALESCE(unit_cost_cents, 0)"))
      # The carrier charges its fee on delivered and on returned parcels.
      fees = orders.where(status: "delivered", delivered_at: start..finish)
        .or(orders.where(status: "returned", returned_at: start..finish)).sum(:sendit_fee)
      delivery = (fees.to_d * 100).round
      ads = advertising_spend(start.to_date..finish.to_date)
      agents = agents_pay(delivered)
      { revenue: revenue, products: goods, delivery: delivery, ads: ads, agents: agents,
        net: revenue - goods - delivery - ads - agents }
    end

    def advertising_spend(dates)
      AdvertisingPerformance.joins(advertising_campaign: :advertising_account)
        .where(advertising_accounts: { store_id: @store.id }, date: dates).sum(:spend_cents)
    end

    # Each agent earns their fixed fee for every delivered order they confirmed.
    def agents_pay(delivered)
      counts = delivered.joins(:order_confirmation).group("order_confirmations.assigned_user_id").count
      return 0 if counts.empty?

      @store.users.where(id: counts.keys).where("pay_per_delivery_cents > 0").pluck(:id, :pay_per_delivery_cents)
        .sum { |id, fee| counts.fetch(id, 0) * fee }
    end

    # Delivered sales and advertising day by day (at least a week, so the chart stays readable).
    def series
      start = period == "today" ? to.beginning_of_day - 6.days : from
      sales = orders.where(status: "delivered", delivered_at: start..to).pluck(:delivered_at, :total_cents)
        .group_by { |at, _| at.in_time_zone(ZONE).to_date }.transform_values { |rows| rows.sum { |_, cents| cents } }
      ads = AdvertisingPerformance.joins(advertising_campaign: :advertising_account)
        .where(advertising_accounts: { store_id: @store.id }, date: start.to_date..to.to_date)
        .group(:date).sum(:spend_cents)
      (start.to_date..to.to_date).map do |day|
        { date: day.iso8601, sales: units(sales.fetch(day, 0)), ads: units(ads.fetch(day, 0)) }
      end
    end

    # Profit of each product on delivered orders of the period; the best four, plus the worst when it loses money.
    def profit_by_product
      rows = OrderItem.where(order_id: delivered_orders(from, to).select(:id)).group(:product_name)
        .pluck(:product_name, Arel.sql("SUM(quantity * unit_price_cents)"), Arel.sql("SUM(quantity * COALESCE(unit_cost_cents, 0))"))
      list = rows.map { |name, revenue, cost| { name: name, profit: units(revenue - cost) } }.sort_by { |row| -row[:profit] }
      top = list.first(4)
      worst = list.last
      top = top.first(3) + [ worst ] if worst && worst[:profit].negative? && top.none? { |row| row[:name] == worst[:name] }
      top
    end

    def latest_orders
      orders.order(created_at: :desc, id: :desc).limit(6).map do |order|
        { id: order.id, number: order.number, customer: order.customer_name, city: order.customer_city,
          total: units(order.total_cents), status: order.status }
      end
    end
  end
end
