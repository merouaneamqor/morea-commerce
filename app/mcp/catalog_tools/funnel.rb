# frozen_string_literal: true

module CatalogTools
  module Funnel
    SUMMARY_FIELDS = <<~GQL.squish
      from to totalVisits abandonedVisits attributedOrders
      sourcesLimit landingsLimit cacheHit
      stages { key visits shareOfLanded dropFromPrevious }
      sources { label visits checkouts orders conversionRate }
      landings { path visits orders }
    GQL

    class FunnelSummary < MCP::Tool
      description <<~TEXT.squish
        Read-only storefront funnel and ad attribution summary for this store.
        Returns cumulative stage counts (landed → product → cart → checkout → ordered),
        top traffic sources, top landing paths, abandoned cart/checkout visits, and Meta-attributed orders.
        Aggregates only — never dumps raw visits or funnel events.
        since/until are YYYY-MM-DD (default last 30 days, max 366).
        sourcesLimit 1–50 (default 25), landingsLimit 1–50 (default 10).
        Results are cached ~45s per store/window.
      TEXT
      input_schema(
        properties: {
          since: { type: "string", description: "YYYY-MM-DD" },
          until: { type: "string", description: "YYYY-MM-DD" },
          sourcesLimit: { type: "integer", description: "1-50, default 25" },
          landingsLimit: { type: "integer", description: "1-50, default 10" }
        }
      )

      def self.call(server_context:, since: nil, until: nil, sourcesLimit: nil, landingsLimit: nil)
        finish = binding.local_variable_get(:until)
        CatalogExecutor.call(
          store: CatalogExecutor.store_from(server_context),
          include_covers: false,
          query: <<~GQL,
            query($since: ISO8601Date, $until: ISO8601Date, $sourcesLimit: Int, $landingsLimit: Int) {
              funnelSummary(
                since: $since, until: $until,
                sourcesLimit: $sourcesLimit, landingsLimit: $landingsLimit
              ) { #{SUMMARY_FIELDS} }
            }
          GQL
          variables: {
            since: since,
            until: finish,
            sourcesLimit: sourcesLimit,
            landingsLimit: landingsLimit
          }.compact
        )
      end
    end

    class FunnelSources < MCP::Tool
      description <<~TEXT.squish
        Top storefront traffic sources (UTM / Meta / TikTok / Google / referral / direct) with visit,
        checkout and order counts for a date window. Same bounds as funnel_summary; does not return raw visits.
        since/until YYYY-MM-DD (default last 30 days, max 366). limit 1–50 (default 25).
      TEXT
      input_schema(
        properties: {
          since: { type: "string", description: "YYYY-MM-DD" },
          until: { type: "string", description: "YYYY-MM-DD" },
          limit: { type: "integer", description: "1-50, default 25" }
        }
      )

      def self.call(server_context:, since: nil, until: nil, limit: nil)
        finish = binding.local_variable_get(:until)
        CatalogExecutor.call(
          store: CatalogExecutor.store_from(server_context),
          include_covers: false,
          query: <<~GQL,
            query($since: ISO8601Date, $until: ISO8601Date, $sourcesLimit: Int) {
              funnelSummary(since: $since, until: $until, sourcesLimit: $sourcesLimit, landingsLimit: 1) {
                from to sourcesLimit
                sources { label visits checkouts orders conversionRate }
              }
            }
          GQL
          variables: { since: since, until: finish, sourcesLimit: limit }.compact
        )
      end
    end

    class FunnelLandings < MCP::Tool
      description <<~TEXT.squish
        Top storefront landing paths by visit count, with orders attributed to those landings.
        Aggregates only. since/until YYYY-MM-DD (default last 30 days, max 366). limit 1–50 (default 10).
      TEXT
      input_schema(
        properties: {
          since: { type: "string", description: "YYYY-MM-DD" },
          until: { type: "string", description: "YYYY-MM-DD" },
          limit: { type: "integer", description: "1-50, default 10" }
        }
      )

      def self.call(server_context:, since: nil, until: nil, limit: nil)
        finish = binding.local_variable_get(:until)
        CatalogExecutor.call(
          store: CatalogExecutor.store_from(server_context),
          include_covers: false,
          query: <<~GQL,
            query($since: ISO8601Date, $until: ISO8601Date, $landingsLimit: Int) {
              funnelSummary(since: $since, until: $until, sourcesLimit: 1, landingsLimit: $landingsLimit) {
                from to landingsLimit
                landings { path visits orders }
              }
            }
          GQL
          variables: { since: since, until: finish, landingsLimit: limit }.compact
        )
      end
    end
  end
end
