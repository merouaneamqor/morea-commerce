# Initial Cashod → Morea gap matrix

2026-10-24. Cashod column is **published**, not authenticated observation. Morea column is **code inspected**, not a live deployment test. E01 must replace preliminary gaps with verified screen/workflow evidence before implementation estimates.

| Domain | Cashod published capability | Morea evidence | Preliminary gap / approach |
|---|---|---|---|
| Tenants and users | Multi-store, custom permissions, 2FA | `app/models/user.rb`, store tenancy and admin staff routes | Specify merchant memberships, granular roles and multi-store switching; retain existing tenant boundary |
| Orders | Multi-source intake, duplicates, deposits | `app/models/order.rb`, admin orders routes | Extend existing state machine and edit locks; specify ingestion/idempotency and outstanding COD |
| Confirmation | Queue, callbacks, attempts, commissions | No dedicated call-center tables in `db/schema.rb` | New queue and attempt/assignment domain |
| WhatsApp / AI | Shared inbox, templates, multilingual confirmation | No messaging domain in schema | Provider connection, consent, inbox, handoff, evaluation and cost controls |
| Delivery | 15 carriers and own-courier runs | Sendit webhook, sync, labels and polling | Extract adapter contract, validate one additional carrier, then delivery runs |
| Returns | Physical verification, restocking and fees | Order `returned` status and inventory movements | Separate parcel status from warehouse receipt and disposition |
| Inventory | Warehouses and FIFO lots | Products, variants and inventory movements | Extend immutable movements with warehouse/lot accounting |
| Procurement | Suppliers, purchase orders, partial receipts | No procurement tables in schema | Add receipt-driven stock/cost ledger after warehouse design |
| Production | Requested-date planning | No dedicated production schema | Specify demand calendar, capacity/stock comparisons and rescheduling |
| Customers | Phone identity, VIP/blacklist | Customers and customer admin routes | Validate intended identity scope; add auditable risk and merge controls |
| Finance | COD reconciliation, profit and cash flow | Platform invoices and order totals | New merchant settlement/accounting domain; preserve separate SaaS invoices |
| Workflows | Triggers, conditions, delays, actions | Sidekiq, schedule, carrier jobs | Event/outbox, replay safety, workflow versioning and execution logs |
| Integrations | Store/Sheets, REST API and MCP | GraphQL, OAuth and MCP routes | Extend current API and decide REST via ADR; add source sync contracts |
| Advertising | Spend attribution, delivered profit, rules | Pixel/tracking settings | New ad account ingestion/reporting domain and guarded automation |
| Plans | Tier limits and subscriptions | Manual tenant invoices and past-due banner | Validate requirements before metering/provider design |
| Localization | Ten app languages | Existing FR/EN/AR and RTL storefront | Preserve current locales; evaluate additional languages after core parity |

Do not infer that a missing table proves a capability cannot exist elsewhere. These entries are planning leads from selected source paths, to be confirmed through focused repository review and authenticated reference observation.
