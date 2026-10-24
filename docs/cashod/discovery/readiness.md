# Readiness audit — 2026-10-24

## Decision

**Start a bounded functional implementation of the core COD back office. Do not claim full Cashod parity or visual fidelity yet.** Morea already contains the storefront, tenant-scoped Rails admin, COD states, stock reservations/movements, Sendit, OAuth, GraphQL and MCP. Extend those foundations; do not replace the commerce app with an assumed Cashod architecture.

The earlier inventory is discovery material, not 240 validated workflows. This audit broadens API/source checks and records explicit failures. UI behavior, writes and external-provider round trips remain unverified. A read returning 200 proves reachable shape, not semantic equivalence.

## Audit results

- 136 GET attempts across the broad static-route sweep, additional dashboard modules and parameter corrections: {'400': 15, '200': 117, '403': 2, '500': 1, '404': 1}. Attempts include repeat routes with corrected query parameters; these are not counts of unique features. Full shape-only results are linked below.
- 14 authenticated dashboard HTML routes checked and 54 additional frontend chunks inspected. These are source checks, not rendered browser/screenshot verification.
- Expanded client catalog: **525 unique method/path-expression pairs**. Some expressions can refer to the same actual route; duplicates/dynamic parameters are not canonicalized into a fake complete OpenAPI. These include untested mutating routes that were discovered but never invoked.
- All 46 MCP definitions classified: {'success': 25, 'not invoked: requires selected record/input': 10, 'error': 6, 'not invoked: mutating action': 5}. Only tools marked read-only without required record inputs were invoked. Mutating tools and selected-record tools were deliberately left untested; some selected-record reads can be exercised later with synthetic fixtures. Successful calls are not a reason to invoke shipping or messaging actions.
- Every accounting route in the sweep succeeded after passing the authorized store as a **query** parameter. The X-Store-Id header alone was insufficient.
- Planning calendar succeeds with `from` and `to` as YYYY-MM-DD; daily view uses `date`. Earlier startDate/endDate attempts were rejected.
- Carrier template-city lookup succeeds with `provider=SENDIT`.
- Analytics advanced/customer/dashboard/product routes were rechecked with the required store query; see audit-analytics-fixes.json for exact outcomes.

## Known blockers and unverified behavior

| Area | Evidence | Consequence |
|---|---|---|
| Browser UI | DEVTOOL warning and about:blank redirect in earlier inspection | Layouts, interaction states, responsive/RTL behavior and screenshots cannot be marked verified |
| Split parcels | GET /split-parcels/settings → 403 | Do not infer inaccessible plan/role behavior or implement it from guessed rules |
| Installed apps | GET /apps/installed → 403; marketplace responds | Installation/entitlement behavior remains unknown |
| Ad dashboard | GET /advertising/dashboard/metrics → 500 | Record as observed source failure, not desired product behavior |
| Settings | GET /users/settings → 404 | Frontend reference may be stale; do not build against it as a working contract |
| MCP read errors | Some customer/product reads report errors | These tools are not established as reliable integration paths; REST successes are separate evidence |
| Public-key REST | Spec downloaded; account API-key list empty | No scoped integration key was created and no authenticated public-key operation was tested |
| Third-party connections | Existing Shopify connection observed; remaining providers are documentation/source evidence | Verify OAuth/scopes, webhook signatures, event mappings, retry and sandbox outcomes before enabling adapters |
| Commercial writes | Not exercised | Order creation/editing, deposits, commissions, dispatch, returns, cash settlement and ad rules need synthetic/sandbox acceptance fixtures |

## Clone coverage map

| Module | Current evidence | Morea approach | Gate before claiming parity |
|---|---|---|---|
| Tenant, roles, navigation | Auth/me, store/role endpoints and dashboard sources | Extend membership/role checks; preserve tenant boundary | Role-denial matrix and UI verification |
| Order desk | Order/list/stat/confirmation reads and frontend requests | Extend existing orders controller/model, events and filters | Synthetic transitions, stock invariants, field validation and UI states |
| Catalog and stock | Product/variant, stock/valuation read shapes, public DTOs | Extend existing products, variants and movements | SKU conflicts, stock concurrency, cost units and return fixtures |
| Confirmation | Queue/counts and successful MCP confirmation reads | Add attempts, callbacks and exclusive assignment | Two-agent claim race and disposition transitions |
| Delivery | Sendit baseline, carrier/shipment/stat reads and assignment-rule source | Adapter contract around existing Sendit | Sandbox dispatch/label/tracking/retry; never use customer orders as tests |
| Returns and FIFO | Read schemas and published lifecycle | Separate physical return receipt from parcel status; ledger extensions | Duplicate receipt/restock and cost reconciliation fixtures |
| Suppliers and purchasing | Supplier/PO reads plus source contracts | Add partial receipt/payment domain | Atomic receipt/lot posting and payables reconciliation |
| Accounting and analytics | Corrected store-scoped report reads | Merchant ledger separate from existing platform invoices | Hand-calculated delivered/returned/deposit/settlement fixtures |
| Workflows | List/templates/stats/execution reads and source request catalog | Transactional event/outbox and bounded executor | Idempotent retry/replay, execution access and action permissions |
| WhatsApp and AI | Account/config/tools/models reads; public messaging source | Separate inbox/provider adapter from model actions | Provider sandbox, opt-out, handoff and spend/permissions controls |
| Store connectors | Existing Shopify, generic integration management requests | Incoming-order adapter first; outbound sync behind feature flag | Signed webhook replay, source ID mapping and per-field ownership |
| Ads and growth | Campaign/adset reads; metrics route fails | Later phase after cash/COGS semantics | Vendor permissions, attribution reconciliation and dry-run budget rules |
| Split parcels and app entitlements | Denied routes | Defer | Obtain authorized feature access and concrete workflow evidence |

## First build slice

1. **Tenant-scoped order desk contract:** document normalized filter/pagination/state fields; preserve Morea::Order transitions, Sendit-owned states, reservation behavior, commercial edit locks and money units. Keep merchant and platform scopes separate.
2. **Source ingestion boundary:** add an external source/reference and idempotent intake path with a unique tenant/source/external-ID constraint; replaying one event creates one order. Introduce an outbox for later provider delivery. Do not connect production Shopify sync in the first slice.
3. **Confirmation queue:** add attempts, dispositions, callbacks and atomic agent claims. Map reference confirmation states separately from shipping status; do not overwrite the existing order state machine with one mixed enum.
4. **Operator UI:** implement Morea's own FR/EN/AR operational table/filters/timeline using confirmed contracts; review visual parity only after legitimate browser evidence exists.
5. **Acceptance:** isolated tenant fixtures for duplicate intake, two simultaneous claims, forbidden cross-store access, invalid transitions, reservation/cancellation and provider-event replay. Require migration rollback and existing API compatibility.

These are proposed implementation boundaries, not features implemented by this documentation PR. Existing planning tasks remain open. Use #36 (order foundation) and #37 (confirmation) as parent epics after #34/#50 accept the scoped gap specification. Defer unsupported providers, WhatsApp sending, carrier dispatch, ads writes and financial automation until their specific contract gates pass.

## Reproducibility and evidence handling

Audit files store field/type shapes and HTTP results without record values. Authorized store IDs in query paths are replaced by placeholders. Session tokens remain in private temporary runtime storage, not in the repository. No customer messages, parcel dispatch, budget changes or business-data writes were performed. API login/MCP initialization created only access sessions.

Files: audit-get.json, audit-additional.json, audit-corrections.json, audit-analytics-fixes.json, audit-mcp.json, page-audit.json, expanded-endpoints.json. The original public OpenAPI and provider/source manifests remain alongside them. No production app test was run: this change is documentation/evidence only.
