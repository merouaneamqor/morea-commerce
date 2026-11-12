# frozen_string_literal: true

module Seller
  # The milestone ladder of the dashboard: how far the store's lifetime revenue has gone through six tiers.
  #
  # The figure is the lifetime revenue of delivered orders, read from AccountingStats (the single source of money
  # figures), so it always agrees with Comptabilité. Everything else is arithmetic on that one number:
  # - a tier is unlocked when the revenue reaches its threshold;
  # - the six bars have the same width; a bar is full once its tier is unlocked, and the next one fills in
  #   proportion to (revenue - previous threshold) / (threshold - previous threshold);
  # - the current tier is the last unlocked one (none below the first threshold).
  # Whole centimes and integer maths for the amounts; percentages are rounded down so 99.9 % never reads 100 %.
  class RevenueMilestones
    # [key, French name, threshold in MAD, colour of the stage]
    TIERS = [
      [ "pionnier", "Pionnier", 100_000, "#3aa76d" ],
      [ "doyen", "Doyen", 500_000, "#3b82c4" ],
      [ "leader", "Leader", 2_000_000, "#7c5cd6" ],
      [ "maitre", "Maître", 5_000_000, "#e08a2c" ],
      [ "legende", "Légende", 10_000_000, "#d6455d" ],
      [ "titan", "Titan", 50_000_000, "#1c1c1e" ]
    ].freeze

    Tier = Data.define(:key, :name, :threshold_cents, :unlocked, :fill, :color)

    attr_reader :revenue_cents

    def initialize(store:, now: Time.current)
      @store = store
      @today = DateRange.today(now)
      @revenue_cents = lifetime_revenue_cents
    end

    def tiers
      @tiers ||= begin
        previous = 0
        TIERS.map do |key, name, mad, color|
          threshold = mad * 100
          fill = if revenue_cents >= threshold then 100
          elsif revenue_cents > previous then ((revenue_cents - previous) * 100 / (threshold - previous))
          else 0
          end
          tier = Tier.new(key: key, name: name, threshold_cents: threshold, unlocked: revenue_cents >= threshold, fill: fill, color: color)
          previous = threshold
          tier
        end
      end
    end

    # Where the single track is filled to, as a percent of its whole length (the six bars have the same width).
    def overall_fill = (tiers.sum(&:fill) / TIERS.size.to_f).round(2)

    def current = tiers.select(&:unlocked).last
    def next_tier = tiers.find { |tier| !tier.unlocked }
    def maxed? = next_tier.nil?
    def remaining_cents = next_tier ? next_tier.threshold_cents - revenue_cents : 0

    # Progress between the current tier and the next one, whole percent (rounded down).
    def percent_to_next
      return 100 if maxed?

      floor = current&.threshold_cents || 0
      (revenue_cents - floor) * 100 / (next_tier.threshold_cents - floor)
    end

    private

    def lifetime_revenue_cents
      first_order = @store.orders.minimum(:created_at)
      return 0 unless first_order

      from = [ first_order.in_time_zone(DateRange::ZONE).to_date, @today - (DateRange::MAX_DAYS - 1) ].max
      range = DateRange.build(from, @today, today: @today)
      return 0 unless range

      Rails.cache.fetch([ "revenue-milestones", @store.id, @store.orders.maximum(:updated_at)&.to_i, @today.iso8601 ], expires_in: 10.minutes) do
        AccountingStats.new(store: @store, range: range).totals.revenue
      end
    end
  end
end
