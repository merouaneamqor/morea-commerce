module Confirmations
  # The agents side by side: the same figures as the single-agent view (Confirmations::Analytics#metrics), one set per agent,
  # and the team median of each figure over the agents who had orders. The median and the gap to it are what the page colours.
  class AgentComparison
    # Which direction is good for each figure; nil = neither (shown without a colour).
    DIRECTION = { delivered_per_100: :higher, confirmation_rate: :higher, delivery_rate: :higher, return_rate: :lower, fake_rate: :lower,
                  median_first_call: :lower, calls_per_order: nil, perseverance: :higher, short_calls: :lower, talk_median: :higher }.freeze
    METRICS = DIRECTION.keys.freeze

    Row = Data.define(:user, :analytics, :metrics)

    def initialize(store:, from:, to:, range:, now: Time.current)
      @store, @from, @to, @range, @now = store, from, to, range, now
    end

    # Everybody who works the desk (the owner and the confirmation agents and supervisors), the busiest first. Someone with no order in
    # the range stays in the list with empty figures, and is left out of the medians.
    def rows
      @rows ||= people.map do |user|
        analytics = Analytics.new(store: @store, from: @from, to: @to, range: @range, agent: user, now: @now)
        Row.new(user: user, analytics: analytics, metrics: analytics.metrics)
      end.sort_by { |row| [ -row.analytics.assigned, row.user.id ] }
    end

    def median(metric)
      values = rows.filter_map { |row| row.metrics[metric] }.sort
      return if values.empty?

      middle = values.size / 2
      values.size.odd? ? values[middle] : ((values[middle - 1] + values[middle]) / 2.0).round(1)
    end

    # :good, :bad or nil, for a value against the team median.
    def verdict(metric, value)
      reference = median(metric)
      direction = DIRECTION[metric]
      return if value.nil? || reference.nil? || direction.nil? || value == reference

      (direction == :higher) == (value > reference) ? :good : :bad
    end

    private

    def people
      @store.users.active.where(admin: true).or(@store.users.active.where(confirmation_role: User::CONFIRMATION_ROLES)).order(:name, :id).to_a
    end
  end
end
