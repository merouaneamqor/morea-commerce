# frozen_string_literal: true

module Admin
  # Read-only shipment cohort, using current order states. Never dispatches or
  # refreshes parcels while serving the dashboard.
  class DeliverySummary
    ZONE = "Africa/Casablanca"
    GROUPS = {
      "collection" => %w[confirmed preparing awaiting_pickup],
      "in_delivery" => %w[picked_up in_transit out_for_delivery],
      "issues" => Order::PROBLEM_STATUSES,
      "delivered" => %w[delivered],
      "returned" => %w[returned],
      "cancelled" => %w[cancelled]
    }.freeze
    attr_reader :store, :start_date, :end_date, :counts, :total, :recent_orders,
      :couriers, :average_days, :status, :query

    def initialize(store:, start_date: nil, end_date: nil, status: nil, query: nil, now: Time.current)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      today = now.in_time_zone(ZONE).to_date
      @end_date = [ parse_date(end_date) || today, today ].min
      @start_date = parse_date(start_date) || @end_date - 29
      @start_date = @end_date - 29 if @start_date > @end_date
      @start_date = [ @start_date, @end_date - 365 ].max
      @status = GROUPS.key?(status) ? status : nil
      @query = query.to_s.strip.truncate(100, omission: "")
      bounds = @start_date.in_time_zone(ZONE).beginning_of_day..[ @end_date.in_time_zone(ZONE).end_of_day, now ].min
      orders = store.orders.where(created_at: bounds)
      @shipments = orders.where.not(status: %w[new confirmed cancelled])
        .or(orders.where.not(sendit_code: [ nil, "" ]))
        .where.not(status: "new")
      raw_counts = @shipments.group(:status).count
      @counts = GROUPS.transform_values { |statuses| statuses.sum { |value| raw_counts.fetch(value, 0) } }
      @total = counts.values.sum
      @average_days = duration(@shipments)
      @couriers = [ [ "Sendit", @shipments.where.not(sendit_code: [ nil, "" ]) ],
                    [ "Manual", @shipments.where(sendit_code: [ nil, "" ]) ] ].map do |name, scope|
        count = scope.count
        delivered = scope.where(status: "delivered").count
        { name: name, total: count, delivered: delivered,
          rate: count.zero? ? 0 : (delivered * 100.0 / count).round(1),
          average_days: duration(scope), last_sync: name == "Sendit" ? scope.maximum(:sendit_synced_at) : nil }
      end
      list = @status ? @shipments.where(status: GROUPS.fetch(@status)) : @shipments
      if @query.present?
        value = "%#{Order.sanitize_sql_like(@query)}%"
        list = list.where("number ILIKE :q OR customer_name ILIKE :q OR customer_city ILIKE :q OR sendit_code ILIKE :q", q: value)
      end
      @recent_orders = list.order(created_at: :desc, id: :desc).limit(30).to_a
    end

    def percentage(group)
      total.zero? ? 0 : (counts.fetch(group) * 100.0 / total).round(1)
    end

    private

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def duration(scope)
      seconds = scope.where(status: "delivered").where.not(shipped_at: nil, delivered_at: nil)
        .where("delivered_at >= shipped_at")
        .average(Arel.sql("EXTRACT(EPOCH FROM (delivered_at - shipped_at))"))
      (seconds / 86_400.0).round(1) if seconds
    end
  end
end
