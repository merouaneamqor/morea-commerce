# frozen_string_literal: true

module Catalog
  # Store-scoped, date-bounded funnel/attribution aggregates for GraphQL and MCP.
  # Never returns raw visit or funnel_event rows.
  class Funnel
    class Error < StandardError; end

    CACHE_TTL = 45.seconds
    MAX_SOURCES = Storefront::FunnelSummary::MAX_SOURCES_LIMIT
    MAX_LANDINGS = Storefront::FunnelSummary::MAX_LANDINGS_LIMIT

    Summary = Data.define(
      :from, :to,
      :total_visits, :abandoned_visits, :attributed_orders,
      :stages, :sources, :landings,
      :sources_limit, :landings_limit, :cache_hit
    )
    Stage = Data.define(:key, :visits, :share_of_landed, :drop_from_previous)
    Source = Data.define(:label, :visits, :checkouts, :orders, :conversion_rate)
    Landing = Data.define(:path, :visits, :orders)

    def self.summary(store, since: nil, until_on: nil, sources_limit: nil, landings_limit: nil)
      from, to = Catalog::Analytics.period(since, until_on)
      sources_cap = clamp(sources_limit, Storefront::FunnelSummary::DEFAULT_SOURCES_LIMIT, MAX_SOURCES)
      landings_cap = clamp(landings_limit, Storefront::FunnelSummary::DEFAULT_LANDINGS_LIMIT, MAX_LANDINGS)
      cache_key = [
        "catalog/funnel_summary",
        store.id,
        from.iso8601,
        to.iso8601,
        sources_cap,
        landings_cap
      ]

      hit = Rails.cache.exist?(cache_key)
      payload = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        range = from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
        Storefront::FunnelSummary.new(
          store: store,
          range: range,
          sources_limit: sources_cap,
          landings_limit: landings_cap
        ).as_payload
      end

      wrap(from, to, payload.to_h.deep_symbolize_keys, cache_hit: hit)
    end

    def self.wrap(from, to, payload, cache_hit:)
      Summary.new(
        from: from,
        to: to,
        total_visits: payload.fetch(:total_visits),
        abandoned_visits: payload.fetch(:abandoned_visits),
        attributed_orders: payload.fetch(:attributed_orders),
        stages: payload.fetch(:stages).map { |row| Stage.new(**row) },
        sources: payload.fetch(:sources).map { |row| Source.new(**row) },
        landings: payload.fetch(:landings).map { |row| Landing.new(**row) },
        sources_limit: payload.fetch(:sources_limit),
        landings_limit: payload.fetch(:landings_limit),
        cache_hit: cache_hit
      )
    end
    private_class_method :wrap

    def self.clamp(value, default, max)
      n = value.to_i
      n = default if n <= 0
      n.clamp(1, max)
    end
    private_class_method :clamp
  end
end
