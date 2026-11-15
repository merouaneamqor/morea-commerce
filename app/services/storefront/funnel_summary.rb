# frozen_string_literal: true

module Storefront
  # Merchant-facing totals: funnel reach, drop-offs, and visit sources for a date range.
  # Aggregates in SQL with hard caps so admin and MCP never dump raw visit/event rows.
  class FunnelSummary
    Stage = Data.define(:key, :visits, :share_of_landed, :drop_from_previous)
    Source = Data.define(:label, :visits, :checkouts, :orders, :conversion_rate)
    Landing = Data.define(:path, :visits, :orders)

    DEFAULT_SOURCES_LIMIT = 25
    DEFAULT_LANDINGS_LIMIT = 10
    MAX_SOURCES_LIMIT = 50
    MAX_LANDINGS_LIMIT = 50

    # Mirrors StorefrontVisit#source_label without loading rows.
    SOURCE_LABEL_SQL = <<~SQL.squish.freeze
      CASE
        WHEN NULLIF(meta_campaign_id, '') IS NOT NULL THEN 'meta'
        WHEN LOWER(utm_source) IN ('facebook', 'ig', 'instagram', 'meta') THEN 'meta'
        WHEN NULLIF(ttclid, '') IS NOT NULL THEN 'tiktok'
        WHEN LOWER(utm_source) IN ('tiktok', 'tt') THEN 'tiktok'
        WHEN NULLIF(gclid, '') IS NOT NULL THEN 'google'
        WHEN LOWER(utm_source) IN ('google', 'adwords') THEN 'google'
        WHEN NULLIF(utm_source, '') IS NOT NULL THEN utm_source
        WHEN NULLIF(referrer, '') IS NOT NULL THEN 'referral'
        ELSE 'direct'
      END
    SQL

    def initialize(store:, range:, sources_limit: nil, landings_limit: nil)
      @store = store
      @range = range.respond_to?(:time_range) ? range.time_range : range
      @sources_limit = clamp_limit(sources_limit, DEFAULT_SOURCES_LIMIT, MAX_SOURCES_LIMIT)
      @landings_limit = clamp_limit(landings_limit, DEFAULT_LANDINGS_LIMIT, MAX_LANDINGS_LIMIT)
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
      label = Arel.sql(SOURCE_LABEL_SQL)
      checkout_stages = %w[checkout_started ordered]
      rows = visits
        .group(label)
        .order(Arel.sql("COUNT(*) DESC"), label)
        .limit(@sources_limit)
        .pluck(
          label,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN funnel_stage IN (#{quoted_list(checkout_stages)}) THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN funnel_stage = 'ordered' THEN 1 ELSE 0 END)")
        )

      rows.map do |name, visit_count, checkouts, orders|
        visit_count = visit_count.to_i
        orders = orders.to_i
        rate = visit_count.positive? ? (orders.to_f / visit_count * 100).round(1) : 0.0
        Source.new(
          label: name.to_s,
          visits: visit_count,
          checkouts: checkouts.to_i,
          orders: orders,
          conversion_rate: rate
        )
      end
    end

    def top_landings(limit: nil)
      cap = clamp_limit(limit, @landings_limit, MAX_LANDINGS_LIMIT)
      visits.where.not(landing_path: [ nil, "" ])
        .group(:landing_path)
        .order(Arel.sql("COUNT(*) DESC"), :landing_path)
        .limit(cap)
        .pluck(
          :landing_path,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN funnel_stage = 'ordered' THEN 1 ELSE 0 END)")
        )
        .map do |path, count, orders|
          Landing.new(path: path, visits: count.to_i, orders: orders.to_i)
        end
    end

    def attributed_orders
      @store.orders.where(created_at: @range).where.not(meta_campaign_id: nil).count
    end

    def as_payload
      {
        total_visits: total_visits,
        abandoned_visits: abandoned_visits,
        attributed_orders: attributed_orders,
        stages: stages.map { |row| row.to_h },
        sources: sources.map { |row| row.to_h },
        landings: top_landings.map { |row| row.to_h },
        sources_limit: @sources_limit,
        landings_limit: @landings_limit
      }
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

    def clamp_limit(value, default, max)
      n = value.to_i
      n = default if n <= 0
      n.clamp(1, max)
    end

    def quoted_list(values)
      values.map { |value| ActiveRecord::Base.connection.quote(value) }.join(", ")
    end
  end
end
