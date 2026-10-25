# frozen_string_literal: true

module Admin
  # Order metrics describe the current state of a received-order cohort, rather
  # than payment settlement or events completed during the selected period.
  class OverviewMetrics
    ZONE = "Africa/Casablanca"
    CONFIRMED_STATUSES = (Order::STATUSES - %w[new cancelled]).freeze
    DAILY_DATE = Arel.sql("((orders.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Africa/Casablanca')::date")

    attr_reader :days, :starts_at, :ends_at, :orders_count, :confirmed_count,
      :confirmation_rate, :delivered_values, :previous_orders_count,
      :previous_confirmation_rate, :previous_delivered_values, :status_counts,
      :daily_values, :pending_orders, :campaigns, :advertising_summary, :reported_ad_contribution, :ad_reporting_present

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
      previous_statuses = previous.group(:status).count
      @previous_orders_count = previous_statuses.values.sum
      @previous_confirmation_rate = rate(confirmed_total(previous_statuses), previous_orders_count)
      @delivered_values = money_values(current.where(status: "delivered"))
      @previous_delivered_values = money_values(previous.where(status: "delivered"))
      summarize_daily(current)
      @pending_orders = store.orders.active.where(status: "new", sendit_code: [ nil, "" ], created_at: ..ends_at)
        .includes(:order_items, order_confirmation: :assigned_user).order(:created_at, :id).limit(5).to_a
      @advertising_summary = AdvertisingSummary.new(store: store, start_date: starts_at.to_date.iso8601,
        end_date: ends_at.to_date.iso8601, sort: "profit")
      @reported_ad_contribution = advertising_summary.profit(advertising_summary.totals)
      reported_ids = AdvertisingPerformance.where(advertising_campaign_id: advertising_summary.campaigns.select(:id),
        date: starts_at.to_date..ends_at.to_date).distinct.pluck(:advertising_campaign_id).to_set
      @ad_reporting_present = reported_ids.any?
      @campaigns = advertising_summary.rows.select { |row| reported_ids.include?(row[:campaign].id) }.first(4).map do |row|
        row.merge(contribution_cents: advertising_summary.profit(row[:metrics]), roas: advertising_summary.roas(row[:metrics]))
      end
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
