module Confirmations
  # Everything the call-center "Analyses" page prints, from the orders created in the range (the cohort) and the calls
  # recorded in it. Printing only: no figure is computed in the view. With an agent, the cohort is the orders that agent
  # called and the calls are hers.
  #
  # How each figure is counted (the page says it too):
  # - Assigned: orders created in the range. Reached: those with at least one call that got an answer (confirmed, cancelled,
  #   callback or wrong number), or that were confirmed. Confirmed: confirmed_at is set. Shipped: confirmed orders handed
  #   to the carrier (shipped, delivered or returned). Delivered: delivered_at is set.
  # - Rates are percentages with one decimal; nil when the denominator is 0, so the page prints "—", not 0 %.
  # - The first call is the first recorded call after the order was created; the median ignores orders never called.
  # - "Confirmed at which call": the position of the call that confirmed, among the recorded calls of that order.
  # - The waiting queue is live (not limited to the range): new orders with no call recorded yet.
  class Analytics
    PROVISIONAL_DAYS = 7
    ANSWERED = %w[confirmed cancelled callback wrong_number].freeze
    OUTCOMES = %w[confirmed no_answer cancelled callback wrong_number abandoned].freeze
    FIRST_CALL_BUCKETS = [ [ :lt15, 0, 15 * 60 ], [ :lt60, 15 * 60, 60 * 60 ], [ :lt3h, 60 * 60, 3 * 3600 ], [ :lt24h, 3 * 3600, 24 * 3600 ], [ :gt24h, 24 * 3600, nil ] ].freeze
    QUEUE_BUCKETS = [ [ :lt1h, 0, 3600 ], [ :lt6h, 3600, 6 * 3600 ], [ :lt24h, 6 * 3600, 24 * 3600 ], [ :gt24h, 24 * 3600, nil ] ].freeze
    MIN_CALLS_FOR_SLOT = 5
    TOP_REASONS = 5

    Row = Data.define(:id, :created_at, :confirmed_at, :shipped_at, :delivered_at, :returned_at)
    Call = Data.define(:order_id, :outcome, :created_at, :user_id)

    attr_reader :agent

    def initialize(store:, from:, to:, range:, agent: nil, now: Time.current)
      @store, @from, @to, @range, @agent, @now = store, from, to, range, agent, now
    end

    def days = (@from..@to).to_a

    # --- funnel -----------------------------------------------------------------------------------------------------
    def assigned = orders.size
    def reached = reached_ids.size
    def confirmed = orders.count(&:confirmed_at)
    def shipped = orders.count { |order| order.confirmed_at && (order.shipped_at || order.delivered_at || order.returned_at) }
    def delivered = orders.count(&:delivered_at)

    def funnel
      [ [ :assigned, assigned, nil ], [ :reached, reached, pct(reached, assigned) ], [ :confirmed, confirmed, pct(confirmed, reached) ],
        [ :shipped, shipped, pct(shipped, confirmed) ], [ :delivered, delivered, pct(delivered, shipped) ] ]
    end

    def confirmation_rate = pct(confirmed, assigned)
    def delivery_rate = pct(delivered, confirmed)
    def delivered_per_100 = pct(delivered, assigned)

    # --- per day ----------------------------------------------------------------------------------------------------
    # One entry per day of the range, in the store's time zone. The newest days are provisional: parcels still on the road.
    def daily
      @daily ||= begin
        by_day = orders.group_by { |order| local_date(order.created_at) }
        days.map do |day|
          list = by_day[day].to_a
          created, confirmed_count, delivered_count = list.size, list.count(&:confirmed_at), list.count(&:delivered_at)
          { date: day, created: created, confirmed: confirmed_count, unconfirmed: created - confirmed_count, delivered: delivered_count,
            confirmation_rate: pct(confirmed_count, created), delivery_rate: pct(delivered_count, confirmed_count),
            delivered_per_100: pct(delivered_count, created), provisional: day > local_date(@now) - PROVISIONAL_DAYS }
        end
      end
    end

    # --- speed of the first call ------------------------------------------------------------------------------------
    def first_call_seconds
      @first_call_seconds ||= orders.filter_map do |order|
        first = calls_by_order[order.id]&.first
        [ (first.created_at - order.created_at).round, 0 ].max if first
      end
    end

    def median_first_call_seconds
      sorted = first_call_seconds.sort
      return if sorted.empty?

      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
    end

    # [{ key:, orders:, confirmed:, rate: }] by how long the order waited for its first call.
    def first_call_speed
      @first_call_speed ||= FIRST_CALL_BUCKETS.map do |key, low, high|
        in_bucket = orders.select do |order|
          first = calls_by_order[order.id]&.first
          next false unless first

          wait = [ (first.created_at - order.created_at).round, 0 ].max
          wait >= low && (high.nil? || wait < high)
        end
        { key: key, orders: in_bucket.size, confirmed: in_bucket.count(&:confirmed_at), rate: pct(in_bucket.count(&:confirmed_at), in_bucket.size) }
      end
    end

    # --- the waiting queue (live) -----------------------------------------------------------------------------------
    def queue
      @queue ||= begin
        ages = waiting_created_at.map { |created_at| [ (@now - created_at).round, 0 ].max }
        buckets = QUEUE_BUCKETS.map { |key, low, high| { key: key, count: ages.count { |age| age >= low && (high.nil? || age < high) } } }
        { total: ages.size, oldest_seconds: ages.max, buckets: buckets }
      end
    end

    # --- which call confirmed ---------------------------------------------------------------------------------------
    # Appel 1, 2, 3, 4, 5+ among the confirmed orders that have recorded calls.
    def confirmed_at_call
      @confirmed_at_call ||= begin
        positions = orders.select(&:confirmed_at).filter_map do |order|
          calls = calls_by_order[order.id].to_a
          index = calls.index { |call| call.outcome == "confirmed" }
          index && index + 1
        end
        counts = (1..5).map { |n| { position: n, count: positions.count { |p| n == 5 ? p >= 5 : p == n } } }
        { total: positions.size, buckets: counts.map { |bucket| bucket.merge(percent: pct(bucket[:count], positions.size)) } }
      end
    end

    # --- results of the calls (calls made in the range) -------------------------------------------------------------
    def call_results
      @call_results ||= begin
        total = range_calls.size
        list = OUTCOMES.map { |outcome| { outcome: outcome, count: range_calls.count { |call| call.outcome == outcome } } }
        { total: total, outcomes: list.map { |row| row.merge(percent: pct(row[:count], total)) } }
      end
    end

    # --- why the customers cancel -----------------------------------------------------------------------------------
    def cancel_reasons
      @cancel_reasons ||= begin
        reasons = cancelled_orders.map { |reason| reason.to_s.strip.downcase.presence || "" }
        total = reasons.size
        grouped = reasons.tally.sort_by { |reason, count| [ -count, reason ] }
        top = grouped.first(TOP_REASONS)
        others = grouped.drop(TOP_REASONS).sum { |_, count| count }
        rows = top.map { |reason, count| { reason: reason, count: count, percent: pct(count, total) } }
        rows << { reason: :others, count: others, percent: pct(others, total) } if others.positive?
        blank = reasons.count("")
        { total: total, rows: rows, blank: blank, blank_percent: pct(blank, total) }
      end
    end

    # --- load by hour -----------------------------------------------------------------------------------------------
    def hourly
      @hourly ||= begin
        new_orders = Array.new(24, 0)
        made = Array.new(24, 0)
        orders.each { |order| new_orders[local_hour(order.created_at)] += 1 }
        range_calls.each { |call| made[local_hour(call.created_at)] += 1 }
        { new_orders: new_orders, calls: made }
      end
    end

    # --- when the customers answer ----------------------------------------------------------------------------------
    # 7 x 24 cells (Monday first): { calls:, answered:, rate: }, rate nil when no call.
    def answer_heatmap
      @answer_heatmap ||= begin
        cells = Array.new(7) { Array.new(24) { { calls: 0, answered: 0 } } }
        range_calls.each do |call|
          local = call.created_at.in_time_zone(DateRange::ZONE)
          cell = cells[(local.wday - 1) % 7][local.hour]
          cell[:calls] += 1
          cell[:answered] += 1 if ANSWERED.include?(call.outcome)
        end
        cells.map { |row| row.map { |cell| cell.merge(rate: pct(cell[:answered], cell[:calls])) } }
      end
    end

    # Best and worst weekday/hour slots, among the slots with enough calls to mean something.
    def answer_slots
      @answer_slots ||= begin
        slots = answer_heatmap.each_with_index.flat_map do |row, wday|
          row.each_with_index.filter_map { |cell, hour| { wday: wday, hour: hour, rate: cell[:rate] } if cell[:calls] >= MIN_CALLS_FOR_SLOT }
        end
        { best: slots.max_by { |slot| [ slot[:rate], -slot[:hour] ] }, worst: slots.min_by { |slot| [ slot[:rate], slot[:hour] ] } }
      end
    end

    # The agents the page can switch to.
    def agents
      @agents ||= @store.users.active.where(admin: true).or(@store.users.active.where(confirmation_role: "agent")).order(:name, :id).to_a
    end

    private

    def pct(part, whole)
      whole.to_i.zero? ? nil : (part * 100.0 / whole).round(1)
    end

    def local_date(time) = time.in_time_zone(DateRange::ZONE).to_date
    def local_hour(time) = time.in_time_zone(DateRange::ZONE).hour

    def agent_order_ids
      ConfirmationAttempt.joins(:order_confirmation).where(store: @store, user_id: @agent.id).select("order_confirmations.order_id")
    end

    def orders
      @orders ||= begin
        scope = @store.orders.active.where(created_at: @range)
        scope = scope.where(id: agent_order_ids) if @agent
        scope.pluck(:id, :created_at, :confirmed_at, :shipped_at, :delivered_at, :returned_at).map { |row| Row.new(*row) }
      end
    end

    # Every recorded call of the cohort, oldest first, by order.
    def calls_by_order
      @calls_by_order ||= begin
        scope = ConfirmationAttempt.joins(:order_confirmation).where(store: @store, order_confirmations: { order_id: orders.map(&:id) })
        scope = scope.where(user_id: @agent.id) if @agent
        scope.order(:created_at, :id).pluck("order_confirmations.order_id", :outcome, :created_at, :user_id).map { |row| Call.new(*row) }.group_by(&:order_id)
      end
    end

    def reached_ids
      @reached_ids ||= orders.select { |order| order.confirmed_at || calls_by_order[order.id].to_a.any? { |call| ANSWERED.include?(call.outcome) } }.map(&:id)
    end

    # The calls made in the range, whatever the order's creation date.
    def range_calls
      @range_calls ||= begin
        scope = ConfirmationAttempt.joins(:order_confirmation).where(store: @store, created_at: @range)
        scope = scope.where(user_id: @agent.id) if @agent
        scope.pluck("order_confirmations.order_id", :outcome, :created_at, :user_id).map { |row| Call.new(*row) }
      end
    end

    def waiting_created_at
      @store.orders.active.where(status: "new", sendit_code: [ nil, "" ])
        .where.not(id: ConfirmationAttempt.joins(:order_confirmation).where(store: @store).select("order_confirmations.order_id"))
        .pluck(:created_at)
    end

    def cancelled_orders
      scope = @store.orders.active.where(status: "cancelled", cancelled_at: @range)
      scope = scope.where(id: agent_order_ids) if @agent
      scope.pluck(:cancel_reason)
    end
  end
end
