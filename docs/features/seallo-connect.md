# Public Seallo Connect app

Seallo Connect is the public Shopify app (`442094518273`). Its paired React Router service owns Shopify installation, embedded authentication, the official SDK's offline sessions and refresh tokens, and signed webhook forwarding. Morea owns workspace authorization, imports, confirmation, inventory, shipping and privacy processing. Existing standalone Shopify OAuth and legacy signed connections keep their credentials and behavior.

Seallo Connect has **no separate Shopify subscription, app charge, trial, or per-order Shopify allowance**. Merchants connect a Shopify store to a Seallo/Morea workspace without paying for the integration itself. Morea's existing workspace-level subscription and `Store#operational_access?` rules are unchanged. A workspace may still need to meet that policy to use the platform. This change does not cancel leftover Shopify subscriptions that merchants may still hold on deleted Partner plans; clearing those is an owner/Partner Dashboard action outside this repository.

## Installation and authorization

The merchant installs Seallo Connect from Shopify. The app redirects the browser to `/admin/seallo/connect?shop=…&state=…&return_to=…`. A signed-in workspace administrator sees a confirmation page naming the workspace and shop. Confirming POSTs back to Morea, which mints a private 10-minute one-time code bound to that shop and redirects to `return_to` (exactly `SEALLO_APP_URL` + `/connect/callback`) with the state unchanged. Nothing is copied or pasted. The app then signs a request to Morea containing only the shop and code. Morea locks and consumes the stored digest once, rechecks the issuing user's current role/workspace/status, and verifies Shopify shop identity and `read_orders` access through the app's signed read proxy. There is no Shopify plan check on connect.

No submitted workspace ID selects a workspace. Each Seallo shop is globally unique in the database and stays reserved to its original workspace after disconnect. A workspace transfer needs a separately authorized support procedure; disconnect alone does not transfer ownership. Reconnecting is always safe for the owning workspace: a disconnected or active Seallo connection is reactivated and re-verified, and a retired standalone-app connection for the same shop becomes the Seallo connection, keeping its identity and receipt history but dropping the old app's credentials. A manually signed source for the same shop is a different integration and is never converted. Imported order identities and histories survive disconnect, uninstall and reconnect.

Server envelopes bind operation and raw JSON with HMAC-SHA256 and a five-minute timestamp window. Webhook relay signatures additionally bind shop, topic and delivery ID. Shopify's original raw-body HMAC is verified independently. App and bridge secrets are separate. Tokens never cross into Rails for this app.

## Billing and access

| Layer | Rule |
| --- | --- |
| Shopify App Pricing / Partner plans | Not required for Seallo Connect. Public paid plans were removed. Do not make the private `shopify-test` plan a requirement. |
| Connect order allowance | Not enforced. `Connections::SealloAllowance` is a no-op for Connect. |
| Morea workspace access | Unchanged. Sync and webhook intake still require `Store#operational_access?`. |

Legacy `shopify_plan_name`, `shopify_order_limit`, and related columns remain on `store_connections` for historical rows. New connect paths do not refresh Partner entitlement or write those fields as a gate. Cached `shopify_entitled_until` values may still satisfy `Store#operational_access?` for older connections; that grant is not expanded for new free installs.

Privacy handling remains available without a Shopify subscription. Partner account ID is distinct from the Dev Dashboard organization ID; do not substitute one for the other.

## Imports and health

Only `read_orders` is requested: the implemented feature imports order snapshots, not a product/customer directory and not outbound Shopify updates. No `read_customers`, `read_products`, `write_orders` or `read_all_orders` is requested without a corresponding implemented feature. Protected shipping/customer fields still require Shopify protected customer data approval.

App-wide `orders/create` subscriptions forward verified deliveries to `/webhooks/seallo`. Morea reuses `Connections::WebhookIntake`, `OrderNormalizer` and `ShopifyOrderSync`. Eligible unpaid, unfulfilled Moroccan COD/MAD orders without tax or discounts become **New** orders. Receipt identities make webhook/poll overlap idempotent. Imports do not reserve stock, confirm orders, dispatch shipments or mutate Shopify orders.

The first catch-up looks back seven days; subsequent runs use an overlap and a stable bounded window/cursor. Each run handles at most 200 orders; the cursor survives a truncated run. A completed resumed window advances to its original upper bound, not the current time. Shopify's normal recent-order availability still limits very old recovery. Existing line normalization limits apply, including at most 50 polled order lines. Incomplete protected fields or unsupported totals produce actionable rejected receipts.

Health includes connection state, last catch-up, sync state/counts/error. Uninstall is idempotent for a repeated signed event and preserves imported orders. First-seen delayed lifecycle events across a reinstall still require sandbox ordering verification. See [privacy workflows](seallo-privacy.md) for exports, automated redaction and records requiring merchant review.

## Deployment order

1. Review both PRs (this repository and the paired Seallo Connect app). Neither is merged or deployed by development checks.
2. Provision the separate app Render service and persistent session disk from its blueprint; confirm its assigned HTTPS hostname. Set the new app's `SHOPIFY_API_SECRET`, strong shared `SEALLO_BRIDGE_SECRET`, and public app handle as hosting secrets/configuration. Partner billing credentials are not required. Never commit secrets.
3. On Morea set `SEALLO_APP_URL`, matching `SEALLO_BRIDGE_SECRET`, and `SEALLO_SHOPIFY_CLIENT_SECRET` for the **new** app. Preserve existing `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET`, master key and stable `secret_key_base`. Morea's blueprint declares the additive variables.
4. Deploy Morea's additive migrations (if any) and app code, preserving subscription columns on rollback. Ensure the existing Sidekiq worker and Shopify schedule run; when `SHOPIFY_EXTERNAL_CRON` is set, the configured external runner must call the existing Shopify sync task. Never enable live provider sync as a test fixture.
5. Confirm listing copy reflects no Shopify charge. Do not attest to outside-Billing-API approval, change listing settings, or resubmit from documentation alone. Validate config before publishing a new app version.
6. Install only the new app on `dev-morea.myshopify.com`, using synthetic orders. Exercise connect without a Shopify plan, webhook retry, poll overlap, uninstall/reinstall and complete privacy responses. Leftover Shopify subscriptions on deleted plans need separate owner handling.

The separate checkout at `../morea-seallo-connect` excludes uncommitted checkout branding changes and unrelated Meta Ads work in the original checkout.

## Verification

Use `RAILS_ENV=test` with an isolated test-named PostgreSQL database. Specs cover signed request/body/operation tampering, actor and tenant boundaries, expired/replayed codes, concurrent connection claims, free-integration connect/sync (no Shopify plan gate), preserved legacy connections, import replay/cursor recovery, privacy scoping and EN/FR/AR rendering. Provider responses are synthetic. Local checks do not prove live Shopify review approval, Render deployment or live installation.

## Managing disconnected Shopify stores

The Seallo Connect overview includes current and retired OAuth connections belonging to the workspace. Manage opens the connection details, where a disconnected store offers Reconnect in Shopify. This opens that persisted shop's Shopify Apps page: open or install Seallo Connect and approve the existing workspace connection. Keep the old record to reuse its identity and imported history.

The local reconnect operation does not reactivate an OAuth connection or queue imports. Only the existing authorized, signed connection exchange re-verifies it. Manually signed webhook sources keep their existing resume behavior. Delete remains available with its existing imported-order and privacy-history restrictions.
