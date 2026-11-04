module Customers
  # Delivery history per customer (one phone number = one customer) and the segment it implies:
  # loyal = at least one delivered order, at risk = returns that match or exceed deliveries,
  # new = no delivered order yet. Every query is scoped to the store; segment filtering and
  # counts run in SQL so no per-customer data is held in memory beyond the page being shown.
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

    # Segment predicates over the `seg` join below; customers without orders have NULL counts.
    DELIVERED = "COALESCE(seg.delivered, 0)".freeze
    RETURNS = "COALESCE(seg.returns, 0)".freeze
    AT_RISK = "(#{RETURNS} > 0 AND #{RETURNS} >= #{DELIVERED})".freeze
    CONDITIONS = {
      "at_risk" => AT_RISK,
      "loyal" => "(#{DELIVERED} > 0 AND NOT #{AT_RISK})",
      "new" => "(#{DELIVERED} = 0 AND NOT #{AT_RISK})"
    }.freeze

    def initialize(store)
      @store = store
      @stats = {}
    end

    # Loads the stats of the given customers (the page being rendered) in one query.
    def preload(customer_ids)
      ids = Array(customer_ids) - @stats.keys
      return if ids.empty?

      open = Order::FLOW - %w[delivered] + Order::PROBLEM_STATUSES
      rows = @store.orders.where(customer_id: ids).group(:customer_id).pluck(
        :customer_id,
        Arel.sql("COUNT(*) FILTER (WHERE status = 'delivered')"),
        Arel.sql("COUNT(*) FILTER (WHERE status = 'returned')"),
        Arel.sql("COUNT(*) FILTER (WHERE status IN (#{open.map { |s| ActiveRecord::Base.connection.quote(s) }.join(', ')}))"),
        Arel.sql("COALESCE(SUM(total_cents) FILTER (WHERE status = 'delivered'), 0)"),
        Arel.sql("MAX(created_at)")
      )
      rows.each do |id, delivered, returns, in_progress, cents, last|
        @stats[id] = Stats.new(delivered: delivered, returns: returns, in_progress: in_progress, delivered_cents: cents, last_order_at: last)
      end
    end

    def for(customer)
      preload([ customer.id ]) unless @stats.key?(customer.id)
      @stats.fetch(customer.id, EMPTY)
    end

    def counts
      total, at_risk, loyal, new_count = segmented(@store.customers).pick(
        Arel.sql("COUNT(*)"),
        *CONDITIONS.values.map { |condition| Arel.sql("COUNT(*) FILTER (WHERE #{condition})") }
      )
      { "all" => total, "at_risk" => at_risk, "loyal" => loyal, "new" => new_count }
    end

    # Narrows a customers relation to one segment.
    def filter(customers, segment)
      segmented(customers).where(CONDITIONS.fetch(segment))
    end

    private

    def segmented(customers)
      per_customer = @store.orders.group(:customer_id).select(
        :customer_id,
        "COUNT(*) FILTER (WHERE status = 'delivered') AS delivered",
        "COUNT(*) FILTER (WHERE status = 'returned') AS returns"
      )
      customers.joins("LEFT JOIN (#{per_customer.to_sql}) seg ON seg.customer_id = customers.id")
    end
  end
end
