# frozen_string_literal: true

module Storefront
  # Merchant-facing totals: funnel reach, drop-offs, and visit sources for a date range.
  class FunnelSummary
    Stage = Data.define(:key, :visits, :share_of_landed, :drop_from_previous)
    Source = Data.define(:label, :visits, :checkouts, :orders, :conversion_rate)
    Landing = Data.define(:path, :visits, :orders)

    def initialize(store:, range:)
      @store = store
      @range = range.respond_to?(:time_range) ? range.time_range : range
    end

    def visits
      @visits ||= @store.storefront_visits.in_range(@range)
    end

    def total_visits
      visits.count
    end

    def stages
      counts = stage_counts
      landed = counts["landed"].to_i
      previous = nil
      StorefrontVisit::STAGES.map do |key|
        count = counts[key].to_i
        drop = previous && previous.positive? ? ((previous - count).to_f / previous * 100).round(1) : nil
        share = landed.positive? ? (count.to_f / landed * 100).round(1) : 0.0
        row = Stage.new(key: key, visits: count, share_of_landed: share, drop_from_previous: drop)
        previous = count
        row
      end
    end

    def abandoned_visits
      visits.where.not(funnel_stage: "ordered")
        .where(funnel_stage: %w[added_to_cart checkout_started])
        .where(last_seen_at: ...30.minutes.ago)
        .count
    end

    def sources
      rows = visits.limit(5_000).to_a
      grouped = rows.group_by(&:source_label)
      grouped.map do |label, list|
        checkouts = list.count { |v| StorefrontVisit::STAGE_RANK[v.funnel_stage] >= StorefrontVisit::STAGE_RANK["checkout_started"] }
        orders = list.count { |v| v.funnel_stage == "ordered" }
        rate = list.size.positive? ? (orders.to_f / list.size * 100).round(1) : 0.0
        Source.new(label: label, visits: list.size, checkouts: checkouts, orders: orders, conversion_rate: rate)
      end.sort_by { |row| [ -row.orders, -row.visits, row.label ] }
    end

    def top_landings(limit: 10)
      visits.where.not(landing_path: [ nil, "" ])
        .group(:landing_path)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(limit)
        .count
        .map do |path, count|
          orders = visits.where(landing_path: path, funnel_stage: "ordered").count
          Landing.new(path: path, visits: count, orders: orders)
        end
    end

    def attributed_orders
      @store.orders.where(created_at: @range).where.not(meta_campaign_id: nil).count
    end

    private

    def stage_counts
      ranks = StorefrontVisit::STAGE_RANK
      totals = StorefrontVisit::STAGES.index_with(0)
      visits.group(:funnel_stage).count.each do |stage, count|
        rank = ranks[stage]
        next unless rank

        StorefrontVisit::STAGES.each do |name|
          totals[name] += count if ranks[name] <= rank
        end
      end
      totals
    end
  end
end
