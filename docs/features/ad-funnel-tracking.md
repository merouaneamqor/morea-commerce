# Ad visit attribution and storefront funnel

First-party tracking for public storefront visits: ad source (UTM, fbclid, gclid, ttclid, Meta campaign macros) and funnel reach (landed → product → cart → checkout → order).

## Capture

- First-touch attribution is kept in the Rails session on every storefront request so native COD checkout can stamp Meta ids on the order the same way connected-store intake already does.
- `storefront_visits` / `storefront_funnel_events` rows are written only when `measurement_allowed?` is true (same cookie banner gate as Meta/TikTok/GA pixels).
- Stages are recorded from product pages, add-to-cart, checkout show and successful place-order.

## Admin

Seller route `/funnel` (sidebar **Trafic** / **Traffic**). Date-range summary of cumulative funnel stages, sources, landing paths, cart/checkout left without an order, and orders that carry Meta ad ids.

## Not in this page

Ad-platform spend, ROAS and delivery metrics stay in Meta Ads Manager, TikTok and Google Analytics (and `/pixels` / Meta Ads connection). This page does not replace those dashboards.

## Verification

`RAILS_ENV=test bundle exec rspec spec/services/attribution/params_spec.rb spec/services/storefront/visit_tracker_spec.rb spec/services/storefront/funnel_summary_spec.rb spec/requests/storefront_funnel_attribution_spec.rb spec/requests/admin_funnel_spec.rb`
