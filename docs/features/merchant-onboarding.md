# Merchant onboarding

New merchant workspaces open `/dashboard` with a first-run checklist. The panel helps staff connect an order source, add a delivery company, receive a first order and confirm it. A short spotlight tour can highlight the matching sidebar entries.

## Keep onboarding in sync

Any product change that affects how a merchant starts, connects, configures or first uses Seallo must update this onboarding process in the same PR. That includes `Seller::Onboarding` step keys and completion rules, dashboard checklist and tour copy, sidebar `data-onboarding-nav` targets when routes move, and the specs below. Do not leave the checklist pointing at a retired setup path.

## Behaviour

`Seller::Onboarding` is read-only. It derives step completion from the current store only: store connections, active products (when `storefront_enabled`), active delivery accounts or legacy Sendit keys, and orders. Viewing the dashboard never creates connections, products, parcels or confirmation attempts.

External-only workspaces (default after signup) see connect → carrier → first order, then confirm once an order exists. Storefront workspaces also get a catalog step; once products exist that step opens `/admin/online_store` (Boutique en ligne / Online store) so Themes and Customize are reachable from the hub. An optional storefront settings link stays available when the boutique is disabled. The seller sidebar shows Boutique en ligne only when `storefront_enabled` is true.

Staff can dismiss the panel for that browser (`localStorage`, keyed by store id) or finish the tour. The panel disappears for everyone once every applicable step is complete. Confirmation agents never see it; they stay off `/dashboard`.

Copy lives under `dashboard.setup` and `dashboard.onboarding` for French, English and Arabic, including RTL.

## Verification

```sh
RAILS_ENV=test bundle exec rspec spec/services/seller/onboarding_spec.rb spec/requests/seller_dashboard_spec.rb
```

Checks use synthetic tenants and disconnected integrations. No migration or live provider sync is required.
