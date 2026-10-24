# Cashod reverse-engineering project for Morea Commerce

Prepared 2026-10-24. Target: https://app.cashod.ma/. Repository: merouaneamqor/morea-commerce.

## Updated discovery

See [the collected discovery evidence](discovery/README.md): authenticated API login now succeeds, MCP exposes 46 tools, 240 feature candidates and 28 named integrations are inventoried, and 377 frontend request references are catalogued. The initial browser-rendering limitation below still applies to screenshots, but no longer blocks API inspection.

## Evidence and limits

Cashod published reference: https://cashod.ma/llms.txt and https://cashod.ma/llms-full.txt (retrieved 2026-10-24). Public app metadata also describes COD modules. These are vendor claims, not authenticated behavioral evidence. The inspection browser received the login page, then the application logged a DEVTOOL permission warning and navigated to about:blank with JavaScript enabled; disabling JavaScript retrieved the application HTML but did not expose a usable login form. Login and account feature/plan access have NOT been verified. No credentials, cookies, customer records or private account screenshots are included here. E01 closes this gap before implementation parity is accepted.

Morea baseline inspected: README.md, config/routes.rb, db/schema.rb, app/models/order.rb, app/models/user.rb, docs/automation.md. Code presence is not proof of production behavior. Existing Rails/Hotwire admin, tenant storefront, catalog/variants, stock movements, order state machine, Sendit, customers, platform invoices, OAuth, GraphQL and MCP should be extended. Cashod is an operations back office; Morea also has a storefront that must be preserved. Do not replace Rails with a guessed Cashod backend architecture or copy branding/assets.

## Delivery sequence and project operation

Phase 0: evidence and gap specification. Phase 1: tenant permissions and order foundation. Phase 2: operator queues, delivery, returns/stock, customer controls and event reliability. Phase 3: messaging AI, purchasing, reconciliation and connectors. Phase 4: ad management, entitlements and release. Phases are sequencing groups, not promised dates. Exact dependencies are recorded per epic in backlog.json and GitHub issues.

Use Backlog → Ready → In progress → Review → Done; use blocked label plus a blocking issue reference. E01's authenticated evidence is a readiness gate for behavioral parity claims. Owners and dates remain unassigned until staffing is known. Select one bounded implementation story at a time after its evidence/design prerequisites. Each story must link evidence, design/ADR, code/PR and validation results; close only when its specific acceptance criteria pass. Discovery stories may close with documentation, but implementation stories require executable verification. No feature implementation is performed by this planning change.

Definition of ready: observed behavior or explicitly approved Morea design; documented tenant/role boundary; dependencies resolved; synthetic fixtures and expected outputs. Definition of done: acceptance evidence, relevant tests, error/retry states, auditability, FR/EN/AR and RTL review, migration/rollback plan when applicable, no production side effects in tests.

## Scope and evidence template

For each screen record timestamp, role, store, subscription visibility, route, navigation, fields/defaults, validation, table/filter/sort/bulk actions, empty/loading/error states, responsive/RTL behavior and redacted screenshots. For each workflow record precondition, actor, action, resulting state, stock/cash effects, external integration and failure/retry behavior. Observe only the authorized account and normal application traffic; do not ship parcels, message customers, incur subscriptions or change ad budgets to gather evidence. Use vendor sandboxes or synthetic fixtures for writes. Mark each claim `published`, `observed`, `inferred`, `Morea-existing` or `Morea-design`.

## GitHub tracking

Master project: https://github.com/merouaneamqor/morea-commerce/issues/33. Five phase milestones and 14 linked epics with 42 specification work packages have been created. Native Projects v2 access is denied by the current integration. Authenticated capture task E01-T1 is marked blocked with the browser finding.

See [gap matrix](gap-matrix.md) for preliminary source-based gaps and [backlog.json](backlog.json) for all issue URLs.

## Backlog

### E01 — Evidence capture and parity specification

Phase 0. Dependencies: none.

Morea baseline: Published reference inspected; authenticated workflows unverified.

- **E01-T1 Capture authenticated screen and workflow inventory** — Record navigation, URLs, fields, filters, validations, empty/error/loading states and desktop/mobile screenshots for every accessible module; label plan-gated screens. Resolve current blank-page browser behavior before claiming login success.
- **E01-T2 Document observed API contracts and domain state machines** — Capture redacted request/response schemas from normal authorized UI use; map order, confirmation, parcel, return and settlement transitions with actor and stock/cash effects. No inferred endpoint may be marked observed.
- **E01-T3 Publish signed-off feature parity and Morea gap matrix** — For every feature record source, observation level, existing Morea path, gap, priority and acceptance scenario; split verified behavior from published claims and product choices.

### E02 — Tenant access, roles and operational shell

Phase 1. Dependencies: E01.

Morea baseline: Store tenancy, staff, platform admin and FR/EN/AR already exist.

- **E02-T1 Specify operator roles and store switching** — Map Cashod role/store visibility after login; design membership permissions beyond current User.belongs_to store; test deny-by-default access and cross-tenant denial for UI, jobs, GraphQL and MCP.
- **E02-T2 Design dense responsive operations navigation** — Map modules into Morea admin while preserving storefront UX; specify RTL, keyboard navigation, tables, saved filters and accessible error states.
- **E02-T3 Harden sessions and audit actor identity** — Specify optional 2FA, session expiry/revocation, privileged actions and actor/source audit events; validate session and token tenant boundaries in isolated tests.

### E03 — Order intake, deduplication and COD lifecycle

Phase 1. Dependencies: E01, E02.

Morea baseline: Order model already has transitions, edits, archive/tags/events, cancellation and stock reservation.

- **E03-T1 Unify external order ingestion and duplicate detection** — Define source IDs and idempotency keys; repeat delivery creates one order; normalize Moroccan phones; flag likely duplicates without deleting legitimate repeat purchases.
- **E03-T2 Extend the existing order desk from observed parity gaps** — Map reference statuses to Order::TRANSITIONS; specify bulk actions, filters, timelines, assignments, validation and edit locks; preserve carrier-owned statuses and existing order history.
- **E03-T3 Specify deposits and remaining COD balance** — Define deposit recording/reversal, minor-unit currency arithmetic and collectible remainder; carrier amount must equal agreed outstanding balance; prevent overpayment and double counting.

### E04 — Call-center confirmation and agent performance

Phase 2. Dependencies: E03.

Morea baseline: No dedicated call-center tables identified in schema.

- **E04-T1 Design confirmation queue and fair assignment** — Specify callback precedence, assignment rules, concurrent claim locks and reassignment; two agents cannot claim the same order; store and role scope enforced.
- **E04-T2 Model call attempts, outcomes and callbacks** — Record agent, timestamps, duration, disposition and next callback; reference observations determine confirmation/cancellation transitions; unanswered attempts cannot silently confirm orders.
- **E04-T3 Define agent reporting and commissions** — Specify denominator for contact/confirmation/delivery rates and commission eligibility/reversals; fixture totals reconcile to call and delivered-order events.

### E05 — WhatsApp inbox and AI confirmation

Phase 3. Dependencies: E03, E04, E11.

Morea baseline: No WhatsApp inbox/AI confirmation module identified.

- **E05-T1 Design official WhatsApp connection and shared inbox** — Document provider setup, template approval, consent, delivery receipts and tenant-bound conversations; duplicate webhook must not duplicate messages; no live customer messages during discovery.
- **E05-T2 Specify button confirmation and timed follow-ups** — Model confirm/cancel buttons, expiry, already-shipped orders, fallback to call center and opt-out; each event changes an order at most once.
- **E05-T3 Design multilingual AI with human handoff** — Specify Darija/AR/FR/EN/ES evaluation fixtures, confidence policy, source-grounded answers, tool permissions, handoff and spend limits; low-confidence or conflicting customer requests require human review.

### E06 — Carrier adapters, shipment lifecycle and delivery runs

Phase 2. Dependencies: E03.

Morea baseline: Sendit integration, polling, labels and webhooks already exist.

- **E06-T1 Extract a carrier contract around existing Sendit behavior** — Specify create/cancel/label/track capabilities, error taxonomy and status mapping; preserve Sendit ownership, retries and idempotency; prove with recorded/sandbox fixtures.
- **E06-T2 Prioritize and specify additional carrier integrations** — Validate Cashod carrier list and per-carrier fields/coverage from authorized screens and vendor docs; deliver adapter matrix and first additional carrier contract; do not promise all carriers without evidence.
- **E06-T3 Design carrier rules and own-courier delivery runs** — Specify ordered assignment rules, fallback, driver manifests, partial delivery, proof and cash handover; rerunning assignment cannot create duplicate parcels.

### E07 — Returns, warehouses and stock costing

Phase 2. Dependencies: E03, E06.

Morea baseline: Inventory movements, variants and reservation lifecycle exist; no warehouse/FIFO tables identified.

- **E07-T1 Specify return receipt and disposition lifecycle** — Separate carrier returned from physical receipt; scan/inspect accepted, damaged and missing items; restock once only and reconcile fees without rewriting shipment history.
- **E07-T2 Design warehouse balances and immutable stock ledger** — Extend existing movements to locations, transfers, reservations and adjustments; concurrent reservations cannot oversell and ledger/balances reconcile by store, SKU and warehouse.
- **E07-T3 Specify FIFO cost lots and delivered COGS** — Define lot allocation, partial consumption, returns and cost corrections; deterministic fixtures reconcile quantity/value and prevent negative cost-lot balances.

### E08 — Suppliers, purchasing and production planning

Phase 3. Dependencies: E07.

Morea baseline: No supplier/purchase/production tables identified.

- **E08-T1 Model suppliers and purchase order workflow** — Specify unit costs, MOQ, lead times, draft/ordered/partial/received/cancelled transitions and access; receiving twice cannot duplicate stock.
- **E08-T2 Design partial receipt and supplier balances** — Specify receipts, costs, payments and outstanding balances; stock lots created atomically with accepted receipt quantities and reconcile to supplier ledger.
- **E08-T3 Specify made-to-order planning calendar** — Map requested dates to daily SKU demand, available stock and planned production; define rescheduling, timezone, cancellation and shortage behavior.

### E09 — Customer identity and risk signals

Phase 2. Dependencies: E03, E02.

Morea baseline: Customer records and admin customer pages exist.

- **E09-T1 Design tenant-safe customer identity and history** — Validate whether reference identity spans stores; define explicit merchant boundary, normalized phones, merge/unmerge and event provenance; no cross-merchant customer exposure.
- **E09-T2 Specify VIP, blacklist and duplicate review controls** — Capture reason, actor, date and override permission; risk flags explain decisions and never silently discard paid or valid customer orders.
- **E09-T3 Define customer search, retention and export access** — Specify masked list views, authorized detail access, retention/deletion rules and export auditing; fixture tests enforce tenant and role restrictions.

### E10 — COD reconciliation, accounting and profitability

Phase 3. Dependencies: E06, E07.

Morea baseline: Platform subscription invoices exist; these are distinct from merchant COD settlements.

- **E10-T1 Design carrier remittance and invoice matching** — Model expected COD, deposits, delivery/return fees, received cash, discrepancies and settlement state; duplicate statement import cannot book money twice.
- **E10-T2 Specify merchant expense and cash ledgers** — Separate merchant accounting from platform invoices; define immutable entries, reversals, receivables and balances; reconcile opening plus movements to closing balances.
- **E10-T3 Define P&L and operational KPI semantics** — Document revenue recognition, FIFO COGS, courier fees, returns, commissions, ad spend and expenses; publish hand-calculated delivered/returned/partial-settlement fixtures and timezone rules.

### E11 — Workflow automation and reliable event processing

Phase 2. Dependencies: E03.

Morea baseline: Sidekiq, scheduled jobs and Sendit polling already exist.

- **E11-T1 Design event/outbox and deduplicated job execution** — Specify tenant-bound events, transaction boundaries, idempotent consumers, retry/backoff and dead-letter handling; crash/replay cannot duplicate shipments or stock movements.
- **E11-T2 Specify trigger-condition-delay-action workflows** — Map published triggers to observed UI; define conditions, delays, cancellation, versioning and safe preview; limit dangerous actions by permission and environment.
- **E11-T3 Design run history, replay and operational alerts** — Specify redacted logs, correlation IDs, dry-run, scoped replay and alert thresholds; failed external actions remain visible with actionable recovery.

### E12 — Store integrations, public API and MCP parity

Phase 3. Dependencies: E03, E11, E02.

Morea baseline: GraphQL, MCP and OAuth with store tokens already exist.

- **E12-T1 Design external commerce and Sheets connectors** — Prioritize Shopify then validate YouCan/WooCommerce/LightFunnels/Storeep/xPage/Sheets demand; specify mapping, cursors, retries, sync conflicts and import reconciliation.
- **E12-T2 Specify scoped developer API and webhook contracts** — Compare existing GraphQL/MCP with published REST capability; decide REST needs via ADR; define scopes, key rotation, pagination, idempotency, webhook signatures and rate limits.
- **E12-T3 Extend existing MCP coverage and safety contracts** — Map accepted modules to tools/resources; preserve preview/apply/verify and authorization semantics; test schema compatibility, tenant scope and safe errors without secrets.

### E13 — Advertising attribution and campaign rules

Phase 4. Dependencies: E10, E11, E12.

Morea baseline: Pixels/tracking settings exist; ad-account reporting/rules not established.

- **E13-T1 Specify ad account connection and COD attribution** — Validate Meta/TikTok/Google/Snapchat screens and vendor permissions; define attribution keys/windows, timezone and spend freshness; track unmatched spend explicitly.
- **E13-T2 Define delivered-profit campaign reporting** — Join spend to confirmed/delivered/returned orders using versioned attribution rules; verify against accounting fixtures and show stale/missing data.
- **E13-T3 Design guarded campaign automation** — Validate which vendors support pause/enable/budget rules; specify dry-run, limits, cooldowns, audit and rollback; no live budget changes during reverse engineering.

### E14 — SaaS plans, migration and release acceptance

Phase 4. Dependencies: E02, E03, E04, E05, E06, E07, E08, E09, E10, E11, E12, E13.

Morea baseline: Manual platform invoices and soft past-due banners already exist.

- **E14-T1 Specify plan entitlements and usage metering** — Verify current Cashod pricing/limits before adopting; design store/order/user metering and limit behavior; preserve existing manual billing until an explicit payment-provider decision.
- **E14-T2 Plan additive migrations and staged rollout** — Provide ADRs, backfill/reconciliation scripts, feature flags, rollback boundaries and backup/restore rehearsal; preserve Morea storefront, tenant URLs, API contracts and current order data.
- **E14-T3 Define end-to-end parity and operational readiness gate** — Use synthetic tenants for intake→confirmation→shipment→delivery/return→settlement plus duplicate, failure and replay cases; require tenant security, accessibility/RTL, load thresholds, monitoring and owner sign-off before release.

