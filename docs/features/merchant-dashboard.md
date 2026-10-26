# Merchant dashboard

Authenticated merchant staff open `/admin` after sign-in. The dashboard supports a Codify boutique, an external-only workspace receiving orders from Shopify, WooCommerce or YouCan, and a boutique with connected stores. Platform-only administrators continue to `/admin/platform`.

## What the numbers mean

The default period is seven calendar days, including today, in `Africa/Casablanca`. Merchants can select 30 days. Unsupported period values use seven days. The window starts at local midnight on its first day and ends at the current time; future-dated orders are excluded.

Order count, order value, delivered and cancelled counts describe orders **created in the selected period**, including archived orders. Delivered and cancelled are their current statuses, rather than events that occurred during the period. Order value sums stored integer cents, including shipping and cancelled orders. Different currencies are displayed separately; legacy DH values normalize to MAD. It is not collected COD, settled cash, revenue recognition or profit. Per-source order counts and values use the same order creation cohort.

The work queue is independent of that period. It counts active, unarchived orders across all dates: new orders without a carrier parcel, callbacks due now or earlier on those orders, and delivery issues (`address_issue`, `unreachable`, `postponed`). Archived orders do not inflate operational work. The delivery issue shortcut opens the existing order desk filtered to those statuses; callbacks open the confirmation queue filtered to callbacks currently due.

## Overview panels

The six primary cards are net collected revenue, net profit, real orders, delivery success, confirmation rate and average order value. Every card carries a quality state. Net collected revenue is the cash the merchant recorded as received for delivered COD orders (order page → *COD payment*) minus recorded refunds, for the selected received-order cohort. It is **Verified** when no delivered order in the cohort awaits remittance, **Estimated** when some do, and **Missing data** when none has been recorded. Net profit is net collected revenue minus the unit-cost snapshot copied onto each order line (set per product as *Cost per unit*), the Sendit parcel fee, manually reported advertising spend and Expenses entered for the selected dates. It is **Verified** only when net collected revenue is Verified, every collected line has a cost snapshot and every collected order has a recorded carrier fee; otherwise **Estimated**, and **Missing data** with no collected orders. Advertising and expenses are charged by calendar date while revenue and product costs follow the received-order cohort, so a period boundary can shift profit between periods. Net margin is shown only for a single-currency cohort. Real orders is **Estimated** because no durable test-order marker exists. The dashboard never relabels delivered face value or manually reported advertising contribution as collected revenue or verified profit.

Delivery success is delivered orders divided by finalized shipment outcomes (`delivered + returned`) in the selected received-order cohort; it is unavailable before any shipment reaches either outcome. Confirmation remains the existing current-state proxy and is marked **Estimated**. Average order value is the stored merchandise subtotal after discounts, excluding shipping, divided separately by the received-order count for each currency.

The action center uses all-time active operational queues: new orders awaiting confirmation, confirmed/preparing orders without a parcel that are ready to ship, and current delivery exceptions. COD remittance pending counts all-time active delivered orders whose cash has not been recorded as received. The funnel shows received, currently confirmed-or-later, carrier-collected-or-later and delivered counts for the selected received-order cohort; it is a current-state cohort funnel, not an event-throughput report.

The main overview adds 7/30-day comparisons, a daily order-value chart, current order-state distribution, up to five orders awaiting confirmation, and up to four campaigns with manually reported performance. Charts render with locally vendored Chart.js 4.5.1 through a Stimulus controller, with localized tooltips, responsive canvases and Turbo cache cleanup. Exact amounts remain in the server-rendered table and status counts remain in text when JavaScript is unavailable. Chart values preserve integer cents and keep currencies separate; a table provides exact daily amounts. Delivered order value is the face value of orders currently delivered in the selected order-creation cohort. It is not settled cash or accounting revenue.

Confirmation rate measures the fraction of received orders whose current state is confirmed or further along the fulfillment lifecycle, including delivery issues and returns. New and cancelled orders do not count as confirmed; this is a current-state indicator, not historical confirmation-event conversion. Previous-period comparisons use the same Casablanca calendar duration and cutoff time. A zero previous order count has no percentage-change baseline.

Delivery rate measures delivered orders as a percentage of all orders received in the selected cohort, matching the existing store analytics contract. Average gain per sale uses manual advertising reports for the same dates: reported delivered revenue minus reported product/delivery costs and advertising spend, divided by reported delivered orders. It is unavailable when no delivered-order count is reported and remains an operational estimate rather than accounting profit or automatic order attribution.

The overview also shows confirmed-order volume, average order value per currency, and cancellation rate. Its operations momentum score is deliberately transparent and read-only: 35% confirmation rate, 45% delivery rate, and 20% cancellation health (`100 - cancellation rate`), rounded to a score from 0 to 100. Empty periods score zero. Starter, Builder, Momentum and Champion levels plus four achievement badges visualize progress; they do not change orders, billing, staff permissions or provider state.

Campaign contribution comes from the existing manual advertising reports for the selected calendar dates: entered delivered revenue less entered fulfillment costs and advertising spend. It does not represent merchant net profit or automatic order attribution. Paused campaigns remain included in historical reporting. Campaign summaries link to the existing reporting dashboard.

Confirmation work remains independent of the chart period. Orders open the existing order desk and confirmation queue, preserving claim ownership, callbacks, audit history, inventory transitions and Sendit ownership. Viewing the overview never confirms orders, dispatches parcels, changes budgets or contacts providers.

## Getting started and channel health

External-only merchants can open setup for Shopify, WooCommerce and YouCan directly from the dashboard. No local catalog or published boutique is required to receive supported signed orders. Boutique merchants receive catalog and storefront actions appropriate to their setup. Disabled boutiques stay unpublished; viewing the dashboard does not enable shopping routes or modify a connection.

Connection configuration alone is not evidence that orders can be received. A source remains configured until the existing signed intake has verified a delivery. The dashboard distinguishes awaiting delivery, verified, disconnected and sources requiring attention. It shows current rejected receipts and links to the existing setup/receipt history. Rejections count current failed receipt records, not every HTTP retry or unauthenticated request. Provider setup stays manual, and the existing [connected-store limits](connected-store-contracts.md) apply, including YouCan payload completeness.

Recent orders are limited to eight, connection cards to six, and low-stock products to five, with aggregate totals retained. Active failing connections are prioritized. Low-stock alerts only use active tracked catalog products and the existing variant stock rules. Cart activity belongs to published boutiques. All dashboard data is scoped to the authenticated host's store, and French, English and Arabic (RTL) are supported.

## Verification

The recent list excludes archived orders even though archived orders remain part of historical period metrics. Receipt-history timestamps use Casablanca time in all three supported languages, so channel error links remain usable after deliveries exist.

Run against an isolated test database after preparing its schema:

```sh
RAILS_ENV=test bin/rails runner script/merchant_dashboard_smoke.rb
```

The script uses synthetic fixtures in a rolled-back transaction and never contacts providers. It checks exact cents, time boundaries, tenant/session authorization, archive and callback rules, bounded results, channel setup presets, localization and external-only availability. Existing optional storefront and connected-store smoke scripts remain complementary coverage. No new data migration or live synchronization is required by this dashboard slice.
