# Public Seallo Connect app

Seallo Connect is the new public Shopify app (`442094518273`). Its paired React Router service owns Shopify installation, embedded authentication, the official SDK's offline sessions and refresh tokens, and signed webhook forwarding. Morea owns workspace authorization, **Seallo subscription entitlement**, imports, confirmation, inventory, shipping and privacy processing. Existing standalone Shopify OAuth and legacy signed connections keep their credentials and behavior.

## Installation and authorization

The merchant installs Seallo Connect from Shopify. Billing is owned by Seallo (`/abonnement` and workspace subscription pages), not Shopify App Pricing. The app redirects the browser to `/admin/seallo/connect?shop=…&state=…&return_to=…`. A signed-in workspace administrator sees a confirmation page naming the workspace and shop. Confirming POSTs back to Morea, which mints a private 10-minute one-time code bound to that shop and redirects to `return_to` (exactly `SEALLO_APP_URL` + `/connect/callback`) with the state unchanged. Nothing is copied or pasted. The app then signs a request to Morea containing only the shop and code. Morea locks and consumes the stored digest once, rechecks the issuing user's current role/workspace/status, verifies the **workspace's Seallo subscription** (with a temporary Shopify App Pricing fallback for still-active legacy contracts), and verifies Shopify shop identity and `read_orders` access through the app's signed read proxy.

No submitted workspace ID selects a workspace. Each Seallo shop is globally unique in the database and stays reserved to its original workspace after disconnect. A workspace transfer needs a separately authorized support procedure; disconnect alone does not transfer ownership. Reconnecting is always safe for the owning workspace: a disconnected or active Seallo connection is reactivated and re-verified, and a retired standalone-app connection for the same shop becomes the Seallo connection, keeping its identity and receipt history but dropping the old app's credentials. A manually signed source for the same shop is a different integration and is never converted. Imported order identities and histories survive disconnect, uninstall and reconnect.

Server envelopes bind operation and raw JSON with HMAC-SHA256 and a five-minute timestamp window. Webhook relay signatures additionally bind shop, topic and delivery ID. Shopify's original raw-body HMAC is verified independently. App and bridge secrets are separate. Tokens never cross into Rails for this app.

## Billing and order allowances

Seallo owns billing. Authoritative plan names and imported-order allowances come from `config/plans.yml` via `Store#seallo_subscription_access?` and `Connections::SealloEntitlement.attributes_from_store`:

| Plan key | Display name | Monthly USD | Imported orders per billing cycle |
| --- | --- | ---: | ---: |
| free | Gratuit | 0 | Unlimited |
| starter | Starter | 19 | 300 |
| intermediate | Intermediate | 39 | 800 |
| professional | Professional | 79 | 3000 |
| business | Business | 149 | 15000 |

`POST /api/seallo/entitlement` returns the linked shop's current entitlement from the connection's workspace (or a still-valid cached Shopify-legacy period). It never trusts a browser-supplied workspace ID and never calls back into the Shopify app, so order-proxy authorization cannot loop.

**Shopify App Pricing sunset / migration:** public Shopify plans were removed. Merchants with a still-active Shopify contract keep access through the paired app's `{operation:"entitlement",shop}` Partner/Admin check (`Seallo Basic` 30 / `Seallo Pro` 100 / `Seallo Premium` unlimited) until that contract ends. Do not cancel or migrate those subscriptions automatically. Once the Shopify period ends, the workspace needs an active Seallo subscription. Partner credentials remain required only for that fallback path.

Morea caches a verified entitlement for at most 15 minutes and never beyond the current Seallo (or Shopify-legacy) period/trial end. The existing Shopify sync job renews entitlement before sync. Disconnect/uninstall removes this source of access. Billing-service outages fail closed and never grant access. Privacy handling remains available without a subscription.

Allowances count accepted receipts by import time in the current entitlement period. They do not count duplicate deliveries, rejections or local/manual orders. At the limit, intake returns `order_limit_reached`. Charging outside Shopify Billing API requires prior Shopify approval for listing compliance; that approval is an outstanding release dependency and is not attested here.

## Imports and health

Only `read_orders` is requested: the implemented feature imports order snapshots, not a product/customer directory and not outbound Shopify updates. No `read_customers`, `read_products`, `write_orders` or `read_all_orders` is requested without a corresponding implemented feature. Protected shipping/customer fields still require Shopify protected customer data approval.

App-wide `orders/create` subscriptions forward verified deliveries to `/webhooks/seallo`. Morea reuses `Connections::WebhookIntake`, `OrderNormalizer` and `ShopifyOrderSync`. Eligible unpaid, unfulfilled Moroccan COD/MAD orders without tax or discounts become **New** orders. Receipt identities make webhook/poll overlap idempotent. Imports do not reserve stock, confirm orders, dispatch shipments or mutate Shopify orders.

The first catch-up looks back seven days; subsequent runs use an overlap and a stable bounded window/cursor. Each run handles at most 200 orders; the cursor survives a truncated run or a quota pause. A completed resumed window advances to its original upper bound, not the current time. Shopify's normal recent-order availability still limits very old recovery. Existing line normalization limits apply, including at most 50 polled order lines. Incomplete protected fields or unsupported totals produce actionable rejected receipts.

Health includes connection state, last catch-up, sync state/counts/error, plan and order allowance. Uninstall is idempotent for a repeated signed event and preserves imported orders. First-seen delayed lifecycle events across a reinstall still require sandbox ordering verification. See [privacy workflows](seallo-privacy.md) for exports, automated redaction and records requiring merchant review.

## Deployment order

1. Review both PRs. Neither is merged or deployed by development checks.
2. Provision the separate app Render service and persistent session disk from its blueprint; confirm its assigned HTTPS hostname. Set the new app's `SHOPIFY_API_SECRET`, strong shared `SEALLO_BRIDGE_SECRET`, Partner API credentials/ID and public app handle as hosting secrets/configuration. Never commit them.
3. On Morea set `SEALLO_APP_URL`, matching `SEALLO_BRIDGE_SECRET`, and `SEALLO_SHOPIFY_CLIENT_SECRET` for the **new** app. Preserve existing `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET`, master key and stable `secret_key_base`. Morea's blueprint declares the additive variables.
4. Deploy Morea's additive migrations and app code, preserving these columns on rollback. Ensure the existing Sidekiq worker and Shopify schedule run; when `SHOPIFY_EXTERNAL_CRON` is set, the configured external runner must call the existing Shopify sync task. Never enable live provider sync as a test fixture.
5. Configure and verify hosted Shopify plans and welcome links, protected customer data approval, exact app URLs/callbacks, support/privacy/listing materials and reviewer workspace access. Validate config before publishing the new app version.
6. Install only the new app on `dev-morea.myshopify.com`, using synthetic orders and no-charge development plans. Exercise trial/upgrade/cancel/quota, webhook retry, poll overlap, uninstall/reinstall and complete privacy responses. The earlier report that this development shop was unavailable still needs a live CLI check; do not substitute another shop silently.

The separate checkout at `../morea-seallo-connect` excludes uncommitted checkout branding changes and unrelated Meta Ads work in the original checkout.

## Verification

Use `RAILS_ENV=test` with an isolated test-named PostgreSQL database. Specs cover signed request/body/operation tampering, actor and tenant boundaries, expired/replayed codes, concurrent connection claims, billing/allowances, preserved legacy connections, import replay/cursor recovery, privacy scoping and EN/FR/AR rendering. Provider and subscription responses are synthetic. Local checks do not prove live subscription charges, protected data approval, Shopify review approval, Render deployment or live installation.

## Managing disconnected Shopify stores

The Seallo Connect overview includes current and retired OAuth connections belonging to the workspace. Manage opens the connection details, where a disconnected store offers Reconnect in Shopify. This opens that persisted shop's Shopify Apps page: open or install Seallo Connect and approve the existing workspace connection. Keep the old record to reuse its identity and imported history.

The local reconnect operation does not reactivate an OAuth connection or queue imports. Only the existing authorized, signed connection exchange re-verifies it. Manually signed webhook sources keep their existing resume behavior. Delete remains available with its existing imported-order and privacy-history restrictions.
