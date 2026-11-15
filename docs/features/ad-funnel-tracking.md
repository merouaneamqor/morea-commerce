# Ad visit attribution and storefront funnel

First-party tracking for public storefront visits: ad source (UTM, fbclid, gclid, ttclid, Meta campaign macros) and funnel reach (landed → product → cart → checkout → order).

## Capture

- First-touch attribution is kept in the Rails session on every storefront request so native COD checkout can stamp Meta ids on the order the same way connected-store intake already does.
- `storefront_visits` / `storefront_funnel_events` rows are written only when `measurement_allowed?` is true (same cookie banner gate as Meta/TikTok/GA pixels).
- Stages are recorded from product pages, add-to-cart, checkout show and successful place-order.

## Admin

Seller route `/funnel` (sidebar **Trafic** / **Traffic**). Date-range summary of cumulative funnel stages, sources, landing paths, cart/checkout left without an order, and orders that carry Meta ad ids.

## MCP / GraphQL

Read-only aggregates on the merchant MCP (`POST /mcp`) and GraphQL (`funnelSummary`). Same Bearer token as other catalog tools. Never returns raw `storefront_visits` or `storefront_funnel_events` rows.

| Tool | Purpose |
| --- | --- |
| `funnel_summary` | Stages, sources, landings, abandoned carts, Meta-attributed orders |
| `funnel_sources` | Top traffic sources only |
| `funnel_landings` | Top landing paths only |

Arguments: `since` / `until` (`YYYY-MM-DD`, default last 30 days, max 366), `sourcesLimit` / `landingsLimit` or `limit` (1–50). Store-scoped SQL aggregates with index-backed filters; summary payload cached ~45s per store/window.

Example MCP call:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "funnel_summary",
    "arguments": {
      "since": "2026-11-01",
      "until": "2026-11-15",
      "sourcesLimit": 10,
      "landingsLimit": 5
    }
  }
}
```

GraphQL:

```graphql
query {
  funnelSummary(since: "2026-11-01", until: "2026-11-15", sourcesLimit: 10, landingsLimit: 5) {
    from to totalVisits abandonedVisits attributedOrders
    stages { key visits shareOfLanded dropFromPrevious }
    sources { label visits checkouts orders conversionRate }
    landings { path visits orders }
  }
}
```

## Not in this page

Ad-platform spend, ROAS and delivery metrics stay in Meta Ads Manager, TikTok and Google Analytics (and `/pixels` / Meta Ads connection). This page does not replace those dashboards.

## Verification

`RAILS_ENV=test bundle exec rspec spec/services/attribution/params_spec.rb spec/services/storefront/visit_tracker_spec.rb spec/services/storefront/funnel_summary_spec.rb spec/graphql/catalog/funnel_spec.rb spec/requests/storefront_funnel_attribution_spec.rb spec/requests/admin_funnel_spec.rb spec/requests/mcp_funnel_spec.rb`
