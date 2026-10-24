# Codify

Multi-store cash-on-delivery commerce platform for Morocco. Morea is the reference store: luxury modest sportswear storefront + COD admin.

**Storefront:** fashion-house UX (campaign homepage, editorial PDP, restrained blush).  
**Store admin:** dense and operational — not luxurious.  
**Platform:** SaaS owner home for super admins (all tenants).

Stores are subdomain tenants. Each store has its own catalog, staff, orders, and Sendit/Discord credentials.

Merchants can request a Codify storefront or an external-only order-management workspace at `/signup`. Approval preserves that choice. **Settings → Codify storefront** controls public shopping; disabling it keeps admin and integrations available, and enabling it later installs missing theme defaults. Existing stores stay published by default.

**Sales channels → Connected stores** configures signed Shopify, WooCommerce and YouCan order webhooks with source filters, receipt history, disconnect/resume and signing-secret replacement. This first slice uses manual provider webhook setup and supports unpaid Moroccan COD/MAD orders without tax, discounts or extra fees. It preserves external line prices/options without local catalog setup or inventory changes. OAuth installation, historical import, provider updates and stock sync remain future work. YouCan needs complete order relationships and native payload completeness is not yet verified; incomplete events are visibly rejected. See [provider setup and limitations](docs/features/connected-store-contracts.md).

**Overview** is the merchant landing dashboard after sign-in. It adapts setup actions to a Codify storefront, connected stores or both, with 7/30-day order metrics, source health, recent orders and direct links to confirmation, due callbacks and delivery issues. Local inventory appears only when the merchant tracks catalog stock; cart activity appears only for enabled storefronts. Order value preserves cents and separates currencies. See [dashboard metric definitions](docs/features/merchant-dashboard.md).

## Run

```bash
docker compose up --build
```

- Local: http://localhost:3010 is the platform landing page; stores open on subdomains, http://morea.localhost:3010 or http://morea.lvh.me:3010
- Production: **ollazen.com**
  - Platform: https://ollazen.com/admin
  - Store example: https://morea.ollazen.com
  - New tenants: `https://{slug}.ollazen.com` (DNS wildcard already set)
- Super admin: `admin@morea.website` / `morea123` → **/admin/platform**
- Platform-only: `super@morea.website` / `morea123`

```bash
docker compose exec web bin/rails db:migrate db:seed
```

### Create another tenant

From the platform UI (**New workspace**), or:

```bash
docker compose exec web env \
  TENANT_SLUG=atelier TENANT_NAME=Atelier \
  ADMIN_EMAIL=admin@atelier.test ADMIN_PASSWORD=secret \
  bin/rails tenants:create
```

Then open http://atelier.lvh.me:3010 (local). In production, add `{slug}.ollazen.com` as a Custom Domain on the Render `morea` service (or add `*.ollazen.com` + root if on a plan that supports wildcards).

`APP_BASE_DOMAIN=ollazen.com` in production. Set `PLATFORM_DISCORD_WEBHOOK_URL` to get a Discord message for every new access request (`/signup`). Platform admins review requests in **Access requests → Review request** (`/admin/access_requests`), then **Approve and create workspace**. Approved merchant workspaces are listed separately from requests; their public Codify storefront is optional. Locally docker-compose uses `lvh.me`.

### Platform billing

Each store has monthly/yearly billing fields. Super admins issue **manual invoices** from Platform → store → Invoices (draft → issue → mark paid / void). Overdue issued invoices set the store to `past_due` and show a soft banner in store admin; the storefront stays online.

```bash
docker compose exec web bin/rails morea:billing:sync_past_due
```

## Agent API (GraphQL + MCP)

Store owners get the token, MCP snippet, and GraphQL URL under **Admin → Settings → Agent API**.

```bash
docker compose exec web bin/rails stores:api_token[morea]
```

The token is shown once and selects the store. Send `Authorization: Bearer <token>`.

Connected agents should read the MCP resource `morea://catalog` before writing. The same manual is the GraphQL query `{ guide }`. It covers prices (`priceDh` as whole units), fr/en/ar translations, deletes (`confirm: true`), and image uploads.

## Stack

Rails 8 · Hotwire · Tailwind · PostgreSQL · Redis · Sidekiq

## Tenant commerce stays public

Every store continues to serve its own localized catalog, cart and COD checkout. New operational features live in authenticated admin or store-token APIs; the apex remains the platform administration surface.

## COD operations foundation

- **Admin → Confirmations** (`/admin/confirmations`): claim new orders, record confirmed/cancelled/no-answer outcomes, schedule callbacks and release claims. Confirmation reserves inventory without automatically dispatching to Sendit. Labels are available in EN/FR/AR.
- **External order intake** (`POST /api/v1/order_imports`): existing store API/OAuth bearer tokens select the store. Repeated source/external IDs return the same order. New imports do not reserve stock, dispatch parcels or send notifications.
- Repository agents can use three skills under `.agents/skills/` for tenant commerce, COD operations and feature delivery. See `AGENTS.md` and `docs/implementation-workflow.md`.

Feature contracts and test commands: [order intake](docs/features/order-intake.md) and [confirmation queue](docs/features/confirmation-queue.md). Provider webhooks, new carrier adapters, WhatsApp sending, automatic assignment and financial reports remain later phases.

The additive migrations create import identities and confirmation/attempt history. No existing order or storefront data is backfilled or rewritten. A code rollback can leave these tables intact; rolling down their migrations deletes the new operational history and must be planned separately.
