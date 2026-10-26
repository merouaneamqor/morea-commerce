# frozen_string_literal: true

module Admin
  # Order metrics describe the current state of a received-order cohort, rather
  # than payment settlement or events completed during the selected period.
  class OverviewMetrics
    ZONE = "Africa/Casablanca"
    LEVELS = { starter: 0, builder: 40, momentum: 65, champion: 85 }.freeze
    CONFIRMED_STATUSES = (Order::STATUSES - %w[new cancelled]).freeze
    DAILY_DATE = Arel.sql("((orders.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Africa/Casablanca')::date")

    attr_reader :days, :starts_at, :ends_at, :orders_count, :confirmed_count, :previous_confirmed_count,
      :confirmation_rate, :delivery_rate, :delivered_values, :previous_orders_count,
      :previous_confirmation_rate, :previous_delivery_rate, :previous_delivered_values, :status_counts,
      :daily_values, :pending_orders, :campaigns, :advertising_summary, :reported_ad_contribution, :ad_reporting_present,
      :average_order_values, :cancellation_rate, :previous_cancellation_rate,
      :momentum_score, :level_key, :next_level_key, :level_progress, :achievements, :top_products

    attr_reader :net_collected_values, :net_profit_values, :real_orders_count, :delivery_success_rate,
      :merchandise_aov_values, :data_quality, :funnel

    attr_reader :average_gain_per_sale, :net_margin_rate, :cod_pending_count

    def initialize(store:, period: "7", now: Time.current)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      @days = %w[7 30].include?(period) ? period.to_i : 7
      @ends_at = now.in_time_zone(ZONE)
      @starts_at = (ends_at.to_date - (days - 1)).in_time_zone(ZONE).beginning_of_day
      current = store.orders.where(created_at: starts_at..ends_at)
      previous = store.orders.where(created_at: (starts_at - days.days)..(ends_at - days.days))
      @status_counts = current.group(:status).count
      @orders_count = status_counts.values.sum
      @confirmed_count = confirmed_total(status_counts)
      @confirmation_rate = rate(confirmed_count, orders_count)
      @delivery_rate = rate(status_counts.fetch("delivered", 0), orders_count)
      @cancellation_rate = rate(status_counts.fetch("cancelled", 0), orders_count)
      @average_order_values = average_money_values(current, orders_count)
      @merchandise_aov_values = average_merchandise_values(current, orders_count)
      @real_orders_count = orders_count
      finalized_shipments = status_counts.fetch("delivered", 0) + status_counts.fetch("returned", 0)
      @delivery_success_rate = finalized_shipments.positive? ? rate(status_counts.fetch("delivered", 0), finalized_shipments) : nil
      @data_quality = {
        real_orders: :estimated,
        delivery_success: finalized_shipments.positive? ? :verified : :missing,
        confirmation_rate: :estimated,
        average_order_value: :verified
      }
      @funnel = {
        received: orders_count,
        confirmed: confirmed_count,
        shipped: shipped_total(status_counts),
        delivered: status_counts.fetch("delivered", 0)
      }
      previous_statuses = previous.group(:status).count
      @previous_orders_count = previous_statuses.values.sum
      @previous_confirmed_count = confirmed_total(previous_statuses)
      @previous_confirmation_rate = rate(previous_confirmed_count, previous_orders_count)
      @previous_delivery_rate = rate(previous_statuses.fetch("delivered", 0), previous_orders_count)
      @previous_cancellation_rate = rate(previous_statuses.fetch("cancelled", 0), previous_orders_count)
      @delivered_values = money_values(current.where(status: "delivered"))
      @previous_delivered_values = money_values(previous.where(status: "delivered"))
      summarize_top_products(current.where(status: "delivered"))
      summarize_daily(current)
      @pending_orders = store.orders.active.where(status: "new", sendit_code: [ nil, "" ], created_at: ..ends_at)
        .includes(:order_items, order_confirmation: :assigned_user).order(:created_at, :id).limit(5).to_a
      @advertising_summary = AdvertisingSummary.new(store: store, start_date: starts_at.to_date.iso8601,
        end_date: ends_at.to_date.iso8601, sort: "profit")
      @reported_ad_contribution = advertising_summary.profit(advertising_summary.totals)
      reported_deliveries = advertising_summary.totals[:delivered_orders]
      @average_gain_per_sale = reported_ad_contribution.fdiv(reported_deliveries).round if reported_deliveries.positive?
      reported_ids = AdvertisingPerformance.where(advertising_campaign_id: advertising_summary.campaigns.select(:id),
        date: starts_at.to_date..ends_at.to_date).distinct.pluck(:advertising_campaign_id).to_set
      @ad_reporting_present = reported_ids.any?
      @campaigns = advertising_summary.rows.select { |row| reported_ids.include?(row[:campaign].id) }.first(4).map do |row|
        row.merge(contribution_cents: advertising_summary.profit(row[:metrics]), roas: advertising_summary.roas(row[:metrics]))
      end
      summarize_money(current, status_counts.fetch("delivered", 0))
      summarize_momentum
    end

    private

    def confirmed_total(counts)
      CONFIRMED_STATUSES.sum { |status| counts.fetch(status, 0) }
    end

    def rate(numerator, denominator)
      denominator.zero? ? 0.0 : (numerator * 100.0 / denominator).round(1)
    end

    def currency(value)
      value.to_s.upcase == "DH" ? "MAD" : value.to_s.upcase
    end

    def money_values(scope)
      scope.group(:currency).sum(:total_cents).each_with_object({}) do |(code, cents), result|
        normalized = currency(code)
        result[normalized] = result.fetch(normalized, 0) + cents
      end
    end

    def average_money_values(scope, count)
      return {} if count.zero?

      money_values(scope).transform_values { |cents| cents.fdiv(count).round }
    end

    def average_merchandise_values(scope, count)
      return {} if count.zero?

      sums = scope.group(:currency).sum(Arel.sql("subtotal_cents - discount_cents"))
      counts = scope.group(:currency).count
      combined = sums.each_with_object({}) do |(code, cents), result|
        normalized = currency(code)
        result[normalized] ||= { cents: 0, count: 0 }
        result[normalized][:cents] += cents
        result[normalized][:count] += counts.fetch(code)
      end
      combined.transform_values { |values| values[:cents].fdiv(values[:count]).round }
    end

# Cash-basis view of the received-order cohort. Revenue is what the merchant
# actually received (carrier remittance) minus refunds; costs are the unit-cost
# snapshots taken when each order was created and the carrier fee on the parcel.
# Advertising and expenses are charged for the selected dates, not the cohort.
def summarize_money(current, delivered_count)
  collected = current.collected
  collected_count = collected.count
  @cod_pending_count = current.awaiting_remittance.count
  @net_collected_values = normalize_sums(collected.group(:currency).sum(Arel.sql("collected_cents - refunded_cents")))

  items = OrderItem.joins(:order).where(orders: { id: collected.select(:id) })
  cogs = normalize_sums(items.group("orders.currency").sum(Arel.sql("order_items.quantity * COALESCE(order_items.unit_cost_cents, 0)")))
  fees = normalize_sums(collected.group(:currency).sum(Arel.sql("COALESCE(sendit_fee, 0) * 100")))
  costs_complete = !items.where(unit_cost_cents: nil).exists?
  fees_complete = !collected.where(sendit_code: [ nil, "" ]).or(collected.where(sendit_fee: nil)).exists?

  home = currency(@store.currency)
  overhead = advertising_summary.totals[:spend_cents].to_i +
    @store.store_expenses.where(spent_on: starts_at.to_date..ends_at.to_date).sum(:amount_cents)
  @net_profit_values = collected_count.zero? ? {} : net_collected_values.to_h do |code, cents|
    profit = cents - cogs.fetch(code, 0) - fees.fetch(code, 0)
    [ code, code == home ? profit - overhead : profit ]
  end
  sole = net_collected_values.one? ? net_collected_values.first : nil
  @net_margin_rate = sole && sole.last.positive? ? (net_profit_values.fetch(sole.first) * 100.0 / sole.last).round(1) : nil

  collected_quality = if collected_count.zero? then :missing
  elsif @cod_pending_count.zero? then :verified
  else :estimated
  end
  @data_quality[:net_collected_revenue] = collected_quality
  @data_quality[:net_profit] = if collected_count.zero? then :missing
  elsif collected_quality == :verified && costs_complete && fees_complete then :verified
  else :estimated
  end
end

def normalize_sums(sums)
  sums.each_with_object(Hash.new(0)) { |(code, value), result| result[currency(code)] += value.to_i }.to_h
end

    def shipped_total(counts)
      %w[picked_up in_transit out_for_delivery unreachable postponed delivered returned].sum { |status| counts.fetch(status, 0) }
    end

    def summarize_momentum
      @momentum_score = if orders_count.zero?
        0
      else
        (confirmation_rate * 0.35 + delivery_rate * 0.45 + (100 - cancellation_rate) * 0.20).round.clamp(0, 100)
      end
      @level_key = LEVELS.keys.reverse.find { |key| momentum_score >= LEVELS.fetch(key) }
      level_index = LEVELS.keys.index(level_key)
      @next_level_key = LEVELS.keys[level_index + 1]
      current_floor = LEVELS.fetch(level_key)
      next_floor = next_level_key ? LEVELS.fetch(next_level_key) : 100
      @level_progress = next_floor == current_floor ? 100 : ((momentum_score - current_floor) * 100.0 / (next_floor - current_floor)).round.clamp(0, 100)
      @achievements = {
        active_store: orders_count >= 10,
        confirmation_pro: orders_count >= 10 && confirmation_rate >= 80,
        delivery_hero: orders_count >= 10 && delivery_rate >= 60,
        cancellation_guard: orders_count >= 10 && cancellation_rate <= 10
      }
    end

    def summarize_top_products(delivered)
      rows = OrderItem.joins(:order).where(orders: { id: delivered.select(:id) })
        .group(:product_id, :product_name, "orders.currency")
        .order(Arel.sql("SUM(order_items.quantity) DESC"))
        .pluck(:product_id, :product_name, "orders.currency", Arel.sql("SUM(order_items.quantity)"), Arel.sql("SUM(order_items.total_cents)"))
      grouped = rows.group_by { |product_id, name, _currency, _units, _revenue| [ product_id, name ] }
        .map do |(product_id, name), values|
          revenue_values = values.each_with_object(Hash.new(0)) { |row, totals| totals[currency(row[2])] += row[4].to_i }
          [ product_id, name, values.sum { |row| row[3].to_i }, revenue_values ]
        end.sort_by { |row| -row[2] }.first(3)
      products = @store.products.where(id: grouped.filter_map(&:first)).index_by(&:id)
      @top_products = grouped.map do |product_id, name, units, revenue_values|
        { product: products[product_id], name: name, units: units, revenue_values: revenue_values }
      end
    end

    def daily_totals(scope)
      scope.group(DAILY_DATE, :currency).sum(:total_cents).each_with_object({}) do |((date, code), cents), result|
        result[date] ||= {}
        normalized = currency(code)
        result[date][normalized] = result[date].fetch(normalized, 0) + cents
      end
    end

    def summarize_daily(current)
      values = daily_totals(current)
      delivered = daily_totals(current.where(status: "delivered"))
      @daily_values = (starts_at.to_date..ends_at.to_date).map do |date|
        { date: date, values: values.fetch(date, {}), delivered_values: delivered.fetch(date, {}) }
      end
    end
  end
end
