# Merchant onboarding

New merchant workspaces open `/dashboard` with a first-run checklist. The panel helps staff connect an order source, add a delivery company, receive a first order and confirm it. A short spotlight tour can highlight the matching sidebar entries.

## Keep onboarding in sync

Any product change that affects how a merchant starts, connects, configures or first uses Seallo must update this onboarding process in the same PR. That includes `Seller::Onboarding` step keys and completion rules, dashboard checklist and tour copy, sidebar `data-onboarding-nav` targets when routes move, and the specs below. Do not leave the checklist pointing at a retired setup path.

## Behaviour

`Seller::Onboarding` is read-only. It derives step completion from the current store only: store connections, active products (when `storefront_enabled`), active delivery accounts or legacy Sendit keys, and orders. Viewing the dashboard never creates connections, products, parcels or confirmation attempts.

External-only workspaces (default after signup) see connect → carrier → first order, then confirm once an order exists. Storefront workspaces also get a catalog step. An optional storefront settings link stays available when the boutique is disabled.

Staff can dismiss the panel for that browser (`localStorage`, keyed by store id) or finish the tour. The panel disappears for everyone once every applicable step is complete. Confirmation agents never see it; they stay off `/dashboard`.

Copy lives under `dashboard.setup` and `dashboard.onboarding` for French, English and Arabic, including RTL.

## Verification

```sh
RAILS_ENV=test bundle exec rspec spec/services/seller/onboarding_spec.rb spec/requests/seller_dashboard_spec.rb
```

Checks use synthetic tenants and disconnected integrations. No migration or live provider sync is required.

## Optional notifications on iPhone

Notification opt-in remains a per-device action in the existing sidebar, outside the store-wide checklist completion rules in `Seller::Onboarding`. It does not change checklist steps or tour destinations. On iOS/iPadOS 16.4 or later, install from Safari with Share → Add to Home Screen, open that installed app, then enable Order alerts. VAPID must be configured on the server.

The manifest keeps its `/admin` identity and start URL, with scope `/` to include seller pages. The worker registers with scope `/` and waits for its own activation before subscribing, including when an old `/admin` worker still controls the page. It does not cache private data or intercept storefront requests.

Before rollout acceptance, verify on a real iPhone using a synthetic workspace: enable alerts from `/dashboard`, accept permission, receive one test order alert with the app backgrounded, open it into the authorized confirmation page, then disable alerts and confirm delivery stops. Also check an existing installation after upgrading; legacy `/admin` subscriptions may remain until revoked and should be checked for duplicate delivery. Record actual device and iOS version. No production delivery has been verified by the automated tests.
