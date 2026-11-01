# Public Seallo Connect app

Seallo Connect is the new public Shopify app (`442094518273`). Its paired React Router service owns Shopify installation, embedded authentication, the official SDK's offline sessions and refresh tokens, Shopify App Pricing checks, and signed webhook forwarding. Morea owns workspace authorization, imports, confirmation, inventory, shipping and privacy processing. Existing standalone Shopify OAuth and legacy signed connections keep their credentials and behavior.

## Installation and authorization

An authenticated workspace administrator generates a private 10-minute code at **Connected stores → Seallo Connect** (`/admin/seallo/connect`). Code generation remains available before subscription purchase. The administrator chooses a Shopify plan in the embedded app, then enters the code. The app takes the shop identity from its authenticated Shopify session, signs the request to Morea, and submits only the shop and code. Morea locks and consumes the stored digest once, rechecks the issuing user's current role/workspace/status, verifies the shop's subscription, and verifies Shopify shop identity and `read_orders` access through the app's signed read proxy.

No submitted workspace ID selects a workspace. Each Seallo shop is globally unique in the database and stays reserved to its original workspace after disconnect. A workspace transfer needs a separately authorized support procedure; disconnect alone does not transfer ownership. An existing standalone connection for the same shop in the target workspace is preserved and prevents replacement. Imported order identities and histories survive disconnect, uninstall and reconnect.

Server envelopes bind operation and raw JSON with HMAC-SHA256 and a five-minute timestamp window. Webhook relay signatures additionally bind shop, topic and delivery ID. Shopify's original raw-body HMAC is verified independently. App and bridge secrets are separate. Tokens never cross into Rails for this app.

## Billing and order allowances

Use Shopify App Pricing's hosted plans, not legacy Billing API charge creation:

| Plan | Monthly USD | Imported orders per billing cycle | Trial |
| --- | ---: | ---: | --- |
| Starter | 19 | Pending confirmation | 7 days |
| Intermediate | 39 | Pending confirmation | 7 days |
| Professionnel | 59 | Pending confirmation | 7 days |
| Business | 129 | Unlimited | 7 days |

These are the proposed public plans. Order limits for Starter, Intermediate and Professionnel still need confirmation before billing activation. The public copy does not advertise an unconfirmed allowance.

The existing entitlement contract still recognizes `Seallo Basic` (19), `Seallo Pro` (99) and `Seallo Premium` (unlimited), with paired-app pricing item handles `seallo-basic`, `seallo-pro`, `seallo-premium`. Do not deploy the new pricing copy as an active billing offer until this contract, the paired app and Shopify hosted plans are updated together with confirmed limits and canonical plan names/handles. Unknown plans remain rejected. Prices, terms, handles and hosted welcome links must be configured in Shopify before activation. Partner account ID is distinct from the Dev Dashboard organization ID; do not substitute one for the other.

Existing cached allowances may remain valid for up to 15 minutes. This repository does not configure Shopify prices or the paired app. Upgrades remain merchant-selected; there are no automatic tier charges.

Morea caches a verified entitlement for at most 15 minutes and never beyond the current Shopify billing/trial end. Its existing ten-minute Shopify job renews that entitlement before sync, including for a subscription-gated workspace. A verified active Shopify plan grants operational access without altering manual invoice status or existing paid periods. Disconnect/uninstall removes this source of access. Cancellation can take up to the remaining cache lifetime to stop new webhook imports; authenticated app reads verify current subscription state. Privacy handling remains available without a subscription.

Allowances count accepted receipts by import time in Shopify's current billing cycle. They do not count duplicate deliveries, rejections or local/manual orders. The connection lock serializes quota checks with intake. At the limit, intake returns `order_limit_reached`; it creates no order, stock movement or accepted receipt. Polling stops and retains its window/cursor, so a later upgrade or new cycle can recover pending orders instead of advancing past them. A trial with no billing cycle uses the configured seven-day window ending at Shopify's canonical trial end. Trial extensions need additional verification before use.

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
