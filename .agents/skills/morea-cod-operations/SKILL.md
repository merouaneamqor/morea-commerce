---
name: morea-cod-operations
description: Implement Morea COD intake, confirmation, inventory, shipment and money workflows without duplicating orders or breaking existing lifecycle rules.
---

# COD operations

Use for intake, order desk, call attempts, stock, carrier integration, returns or merchant financial features. Read `app/models/order.rb`, `app/services/orders/editor.rb`, `app/graphql/catalog/order_desk.rb`, the relevant Sendit services and existing smoke scripts before editing.

## Use the existing lifecycle

Order shipping state is defined by `Order::TRANSITIONS`, `FLOW`, `RESERVED_STATUSES` and `SENDIT_OWNED_STATUSES`. Use the transition methods; do not bypass them with a direct status update. With Sendit configured, staff cannot set carrier-owned delivery states. Preserve commercial edit locks and inventory adjustments when confirmed order quantities change.

Keep confirmation assignment, call outcomes and callback scheduling in their own domain. A no-answer attempt does not confirm an order. Explicit confirmation/cancellation must use the existing order transition path and be atomic with the attempt record. Serialize competing claims and validate the claimant's tenant membership.

`Orders::Editor` owns staff order creation and line pricing; public checkout has a separate path. Reuse established validation and totals instead of accepting arbitrary product prices or cross-store variant IDs. Inspect side effects: creation enqueues `OrderStatusJob` and `DiscordOrderNotifyJob`; an outer transaction and retries must not leak duplicate notifications or uncommitted order IDs.

## Make external intake replay-safe

Identify imports by authorized store, source and external reference. Enforce uniqueness in the database, not only with a preflight lookup. Replayed events return the existing result; they must not duplicate orders, stock movements, customer counters or jobs. Keep import identity and order creation in one transaction. Check concurrent deliveries and retry-after-timeout behavior. Provider sync, webhook signature validation and outbound updates are separate contracts; do not turn them on merely because intake is implemented.

## Preserve units and stock

Database money fields use integer cents. Several agent APIs expose whole dirham fields such as `priceDh` and `shippingDh`; inspect the specific adapter before converting. Avoid floating-point money calculations, implicit truncation and treating MAD values as cents twice.

New orders do not reserve inventory. Confirmation reserves stock, commercial edits adjust reserved quantity, and cancellation/return flows must follow existing movement semantics. Use atomic updates or locks where competing confirmations can oversell. A carrier's returned status is not automatically evidence that a physical warehouse receipt was verified; model new return workflows explicitly.

Keep merchant COD settlement separate from platform subscription invoices. For new deposits, fees or profit reports define recognition, reversals and reconciliation fixtures before implementation.

## Acceptance checks

Use synthetic test tenants and test job adapters. Cover replay and concurrency, foreign tenant/product/variant IDs, validation rollback, stock before/after confirmation and cancellation, invalid transitions and carrier-owned-state rejection. Relevant existing scripts include `script/mcp_order_desk_smoke.rb` and `script/mcp_inventory_smoke.rb`. Do not dispatch real parcels, send WhatsApp messages, change ad budgets or invoke paid services in tests.

## Reproduce manager-to-agent calls

Use `spec/requests/confirmation_workflow_spec.rb` for the complete HTTP scenario: manager creates a normal order and staff agent, agent signs in and clocks in, starts a call from the queue, saves its outcome, then both users read the saved results. Test HTML forms and explicit JSON clients separately. Never place a real telephone call for this check.

A staff supervisor without Admin access cannot sign in; reject that combination rather than silently creating an unusable account or granting permissions. Confirmation agents remain non-admins. Partial call edits must preserve omitted customer fields and product lines; distinguish omitted lines from an explicit empty collection. In JSON regression requests use `as: :json` when an empty collection must reach the server. Keep the simulated clock advanced while reading reports after a timed call, then restore it.

Sendit runtime options are edited in Integrations; keep them on the authorized Store because parcel dispatch reads those fields. Managed API keys use the existing verified, encrypted DeliveryAccount flow. Integrations rendering must read cached city data only; refreshing is an explicit queued action. When deleting Sendit accounts, test both managed and older fallback credentials so deletion cannot silently reconnect or disconnect a different active account. Preserve orders and webhook history; see docs/features/sendit-settings.md.
