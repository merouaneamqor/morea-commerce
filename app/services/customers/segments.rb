module Customers
  # Delivery history per customer (one phone number = one customer) and the segment it implies:
  # loyal = at least one delivered order, at risk = returns that match or exceed deliveries,
  # new = no delivered order yet. Every query is scoped to the store.
  class Segments
    SEGMENTS = %w[loyal at_risk new].freeze

    Stats = Data.define(:delivered, :returns, :in_progress, :delivered_cents, :last_order_at) do
      def segment
        if returns.positive? && returns >= delivered then "at_risk"
        elsif delivered.positive? then "loyal"
        else "new"
        end
      end
    end

    EMPTY = Stats.new(delivered: 0, returns: 0, in_progress: 0, delivered_cents: 0, last_order_at: nil)

    def initialize(store)
      @store = store
    end

    def stats
      @stats ||= begin
        open = Order::FLOW - %w[delivered] + Order::PROBLEM_STATUSES
        rows = @store.orders.group(:customer_id).pluck(
          :customer_id,
          Arel.sql("COUNT(*) FILTER (WHERE status = 'delivered')"),
          Arel.sql("COUNT(*) FILTER (WHERE status = 'returned')"),
          Arel.sql("COUNT(*) FILTER (WHERE status IN (#{open.map { |s| ActiveRecord::Base.connection.quote(s) }.join(', ')}))"),
          Arel.sql("COALESCE(SUM(total_cents) FILTER (WHERE status = 'delivered'), 0)"),
          Arel.sql("MAX(created_at)")
        )
        rows.to_h { |id, delivered, returns, in_progress, cents, last| [ id, Stats.new(delivered: delivered, returns: returns, in_progress: in_progress, delivered_cents: cents, last_order_at: last) ] }
      end
    end

    def for(customer) = stats.fetch(customer.id, EMPTY)

    def counts
      by_segment = stats.values.map(&:segment).tally
      customers_without_orders = @store.customers.where.not(id: stats.keys).count
      { "all" => stats.size + customers_without_orders,
        "loyal" => by_segment.fetch("loyal", 0),
        "at_risk" => by_segment.fetch("at_risk", 0),
        "new" => by_segment.fetch("new", 0) + customers_without_orders }
    end

    def ids_in(segment)
      stats.select { |_, s| s.segment == segment }.keys
    end
  end
end
