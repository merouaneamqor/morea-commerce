# Cashod discovery evidence — 2026-10-24

## What has now been collected

- 240 feature candidates across 22 modules, with evidence labels in [features.json](features.json).
- 48 feature/integration pages retrieved successfully: 20 feature pages and 28 named integrations. Timestamp/hash manifest: [source-manifest.json](source-manifest.json). The manifest supports reproducibility; raw copyrighted website pages are not copied into the repository.
- Seven public REST operations and seven request schemas from the live [OpenAPI](openapi.json).
- 377 frontend request references in [internal-endpoints.json](internal-endpoints.json); these include duplicates and dynamic expressions, so they are not 377 distinct verified endpoints.
- 22 authenticated GET probes, HTTP results {'200': 19, '400': 2, '404': 1}, with response field/type structures only in [live-verification.json](live-verification.json). Values and customer records are excluded.
- Account authentication succeeded: login HTTP 201, current-user HTTP 200. Session token kept outside the repository in temporary private runtime storage.
- MCP initialization and tools/list succeeded against `https://mcp.cashod.ma/mcp`; all 46 definitions returned, no pagination cursor. Schemas in [mcp-tools.json](mcp-tools.json). No action tools were invoked.
- An existing active Shopify integration is confirmed by account metadata. No new third-party account has been linked, no integration sync was triggered, and no stock/order/message/advertising actions were run.

## Connection surfaces

| Surface | Base | Authentication | Verification |
|---|---|---|---|
| Internal application API | `https://backend.cashod.ma/api` | Account bearer session; `X-Store-Id` for UI selection; `Accept-Language` | Authenticated GET checks succeeded |
| Public integration API | `https://api.cashod.ma` | Store key `csk_live_…`, scoped bearer token | OpenAPI HTTP 200; authenticated public-key calls not tested; account key list is empty |
| MCP | `https://mcp.cashod.ma/mcp` | Session bearer accepted in this inspection; published normal connector flow uses OAuth PKCE | Initialize and tools/list successful |

Browser rendering remains blocked by the app's DEVTOOL check, but the normal account login API succeeded. This resolves the API-access blocker from the initial plan, not the screenshot/browser evidence gap. The MCP root protected-resource discovery path tested returned 404; do not invent discovery metadata from that result. Direct authenticated MCP initialization succeeded.

## Public REST operation inventory

| Method | Path | Operation |
|---|---|---|
| POST | `/api/v1/orders` | Create an order |
| GET | `/api/v1/orders` | List orders |
| GET | `/api/v1/orders/{id}` | Retrieve an order |
| POST | `/api/v1/products` | Create or update a product |
| GET | `/api/v1/products` | List products |
| GET | `/api/v1/products/{id}` | Retrieve a product |
| PATCH | `/api/v1/products/{id}/variants/{variantId}/stock` | Set a variant's stock |

OpenAPI is the primary wire contract. It documents order upsert idempotency through external_id, product/variant SKU matching, stock replacement, request validation and pagination. Public docs specify per-key scopes, 120 requests/minute, list page sizes 50 default/100 maximum, and typed errors. Read/write scopes are separate; product writes that contain stock also require stock:write. An account session is not established as a public API key.

## Third-party integration coverage

[Integrations registry](integrations.json) records 15 carriers, six commerce platforms, Google Sheets, four ad networks, WhatsApp Business and custom webhooks. Carrier countries: Morocco (13), Tunisia/Navex, Panama and Costa Rica/HL Express. Shopify is account-connected. Other named providers are published support, not verified account connections.

Commerce sync directions from the full product reference:

- Shopify: incoming orders/products and stock; outgoing tracking fulfillment, paid state, returns/cancellation and stock.
- YouCan: incoming categories/products/orders; outgoing confirmation/shipping state and stock.
- WooCommerce: incoming products/orders; outgoing confirmed→processing, delivered→completed, returned→refunded and cancellation mappings. These are Cashod's stated mappings, not a reason to issue financial refunds during testing.
- LightFunnels: incoming products/orders; outgoing fulfillment/tracking, paid state and cancellation.
- Storeep: orders/products/inventory. xPage: products/orders. Google Sheets: mapped order/product imports.
- WhatsApp: official Cloud API account linking, templates, inbox, media and workflow actions.
- Meta/TikTok/Google/Snapchat: OAuth-based ad data; automated rules documented for Meta/TikTok/Snapchat. Meta CAPI sends COD lifecycle events.

Additional published dependencies: OpenAI, Anthropic, Google, Groq and DeepSeek for AI/BYOK; SMS/email, Slack, Discord and outbound HTTP workflow actions. Exact provider configuration, credential scopes, API versions and rate limits require per-provider setup inspection; a marketing integration page is insufficient evidence.

## Evidence gaps and next work

This is a broad feature and contract collection, not a claim that every workflow has been exercised. Authenticated endpoint availability proves access and response structure, not every operation's semantics. 400 planning/accounting responses need documented date/store query parameters; /users/settings returned 404. Empty arrays do not prove a module is absent. Frontend references may be stale, plan-gated or unreachable.

Next: capture authorized screen navigation and workflow states; collect per-provider setup contracts, webhooks/signatures, field maps, status mappings and retry behavior; verify query parameters and subscription gates; then refine implementation issues using evidence IDs. Do not connect new merchant providers, dispatch parcels or message customers merely to collect evidence. A production Morea connector is a separate implementation step requiring scope and sync-direction choices.

Sources: https://cashod.ma/en/developers, https://api.cashod.ma/api/v1/openapi.json, https://cashod.ma/llms-full.txt, the 48 page URLs in the manifest, public frontend request client and authenticated read-only account inspection.
