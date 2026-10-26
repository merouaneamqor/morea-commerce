# frozen_string_literal: true

module Admin
  # Read-only merchant overview. The period describes orders received, while
  # operational queues intentionally include active work from every period.
  class DashboardSummary
    PERIODS = %w[7 30].freeze
    ZONE = "Africa/Casablanca"
    RECENT_LIMIT = 8
    CONNECTION_LIMIT = 6
    INVENTORY_LIMIT = 5

    attr_reader :store, :period, :days, :starts_at, :ends_at, :mode,
      :orders_count, :order_value_cents, :order_values, :delivered_count,
      :cancelled_count, :pending_count, :callbacks_due_count, :delivery_issues_count,
      :ready_to_ship_count, :cod_pending_count,
      :recent_orders, :connections, :connections_count, :rejected_count, :source_stats,
      :has_products, :has_orders, :has_tracked_inventory, :low_stock, :low_stock_count,
      :active_carts_count

    def initialize(store:, period: "7", now: Time.current)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
      @period = PERIODS.include?(period) ? period : "7"
      @days = @period.to_i
      @ends_at = now.in_time_zone(ZONE)
      @starts_at = (@ends_at.to_date - (@days - 1)).in_time_zone(ZONE).beginning_of_day
      summarize_orders
      summarize_connections
      summarize_inventory
      @mode = if store.storefront_enabled?
        @connections_count.positive? ? "combined" : "storefront"
      else
        "connected"
      end
    end

    private

    def received_orders
      store.orders.where(created_at: starts_at..ends_at)
    end

    def canonical_currency(value)
      value.to_s.upcase == "DH" ? "MAD" : value.to_s.upcase
    end

    def money_totals(scope)
      scope.group(:currency).sum(:total_cents).each_with_object(Hash.new(0)) do |(currency, cents), totals|
        totals[canonical_currency(currency)] += cents
      end.sort.to_h
    end

    def summarize_orders
      status_counts = received_orders.group(:status).count
      @orders_count = status_counts.values.sum
      @order_values = money_totals(received_orders)
      @order_value_cents = @order_values.fetch(canonical_currency(store.currency), 0)
      @delivered_count = status_counts.fetch("delivered", 0)
      @cancelled_count = status_counts.fetch("cancelled", 0)
      @has_orders = store.orders.exists?

      pending = store.orders.active.where(status: "new", sendit_code: [ nil, "" ])
      @pending_count = pending.count
      @callbacks_due_count = pending.joins(:order_confirmation)
        .where(order_confirmations: { store_id: store.id, disposition: "callback" })
        .where("order_confirmations.callback_at <= ?", ends_at).count
      @delivery_issues_count = store.orders.active.where(status: Order::PROBLEM_STATUSES).count
      @cod_pending_count = store.orders.active.awaiting_remittance.count
      @ready_to_ship_count = store.orders.active.where(status: %w[confirmed preparing], sendit_code: [ nil, "" ]).count
      @recent_orders = store.orders.active.where(created_at: ..ends_at).recent.order(id: :desc)
        .includes(:order_imports, external_order_receipt: :store_connection).limit(RECENT_LIMIT).to_a
      @active_carts_count = store.storefront_enabled? ? store.carts.recent.count : 0
    end

    def summarize_connections
      sources = store.store_connections
      @connections_count = sources.count
      # Pending errors should be visible first, then sources awaiting their
      # first verified delivery. Never infer health from configuration alone.
      priority = <<~SQL.squish
        CASE WHEN active AND last_error_code IS NOT NULL THEN 0
             WHEN active AND verified_at IS NULL THEN 1
             WHEN active THEN 2 ELSE 3 END
      SQL
      @connections = sources.order(Arel.sql(priority), created_at: :desc, id: :desc)
        .limit(CONNECTION_LIMIT).to_a
      receipts = ExternalOrderReceipt.where(store_connection_id: sources.select(:id))
      @rejected_count = receipts.where(status: "rejected").count
      @source_stats = {}
      visible_ids = @connections.map(&:id)
      return if visible_ids.empty?

      amounts = received_orders.joins(:external_order_receipt)
        .where(external_order_receipts: { store_connection_id: visible_ids })
        .group("external_order_receipts.store_connection_id", :currency)
        .pluck(Arel.sql("external_order_receipts.store_connection_id"), :currency,
          Arel.sql("COUNT(*)"), Arel.sql("SUM(orders.total_cents)"))
      rejected = receipts.where(store_connection_id: visible_ids, status: "rejected", received_at: starts_at..ends_at)
        .group(:store_connection_id).count
      visible_ids.each do |id|
        @source_stats[id] = { orders_count: 0, order_value_cents: 0, order_values: {}, rejected_count: rejected.fetch(id, 0) }
      end
      amounts.each do |id, currency, count, cents|
        stats = @source_stats.fetch(id)
        normalized = canonical_currency(currency)
        stats[:orders_count] += count
        stats[:order_values][normalized] = stats[:order_values].fetch(normalized, 0) + cents
        stats[:order_value_cents] += cents if normalized == canonical_currency(store.currency)
      end
    end

    def summarize_inventory
      products = store.products.active
      @has_products = products.exists?
      @has_tracked_inventory = products.where(track_inventory: true).exists?
      inventory = products.low_stock(store.low_stock_threshold)
      @low_stock_count = inventory.count
      @low_stock = inventory.order(:id).includes(:product_variants).limit(INVENTORY_LIMIT).to_a
    end
  end
end
