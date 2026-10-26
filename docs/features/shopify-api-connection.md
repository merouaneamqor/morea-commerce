# Seallo Shopify API connection

Merchants connect the shared Seallo Shopify app from **Sales channels → Connected stores → Shopify**. They enter a connection name and the permanent `example.myshopify.com` domain, select **Connect Shopify**, approve access at Shopify and return to the connection. They never enter an app secret or configure a webhook. English, French and Arabic setup includes server-configuration errors, reauthorization and an explicit API connection test.

## Platform configuration

Create the shared Seallo app in Shopify Dev Dashboard and select an appropriate distribution method for independent merchant installations. Set `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` on the Rails service. Docker Compose forwards those environment variables; Render's blueprint declares them as secrets. Keep the existing stable `secret_key_base` so encrypted tokens remain decryptable.

Register the exact callback generated from `APP_BASE_DOMAIN` and optional `APP_PORT`: in production with the current base domain, `https://ollazen.com/admin/shopify/callback`. The development callback is `http://lvh.me:3010/admin/shopify/callback`; use a configured HTTPS development domain/tunnel when Shopify requires HTTPS. Do not derive the callback from an incoming host header. The merchant's authenticated session selects the workspace on the apex callback host.

Request `write_orders,read_orders,read_customers,read_products`. `write_orders` includes order reads; the verifier accepts implied read permissions from corresponding write scopes. These order scopes cover the last 60 days; older orders require separate `read_all_orders` approval. Protected customer fields require the applicable Shopify data access approval. Granting scopes alone does not prove that customer names, addresses, email or phone fields will be returned.

Authoritative setup: [standalone OAuth](https://shopify.dev/docs/apps/build/authentication-authorization/authenticate-standalone-apps), [access scopes](https://shopify.dev/docs/api/usage/access-scopes), and [offline access tokens](https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens).

## Security and lifecycle

- Only authenticated, subscribed workspace operators can initiate authorization or test their scoped connection. Submitted workspace IDs cannot select another workspace. Platform-only sessions without a workspace are rejected.
- OAuth state is bound to the initiating user, workspace, connection and shop. A SHA-256 digest and 10-minute expiry are persisted, uniquely indexed and consumed under a row lock. Callbacks validate the HMAC over sorted URL-encoded query parameters, reject duplicate query keys and stale timestamps, and consume the state before exchanging the code.
- Access and refresh tokens are encrypted with distinct purposes. Expiring offline tokens are requested (`expiring=1`), refreshed under the connection lock before expiry, and verified through GraphQL shop identity and current installation scopes. HTTP is bounded, uses HTTPS, refuses redirects and emits only fixed error codes. Authorization codes, state and signatures are filtered from logs and omitted from language-switch links on callback errors.
- Disconnect clears locally stored access/refresh tokens and pending state; it does not uninstall the Shopify app. Reconnect requires new approval. Revoked credentials are detected on API use; there is no uninstall webhook subscription. Temporary network/rate-limit failures retain encrypted refresh credentials while clearing verified status.
- Existing imported orders are preserved. Legacy Shopify webhook records continue only until the merchant explicitly completes OAuth migration; API-mode connections accept `orders/create` deliveries only when signed with the shared app secret; a delivery signed with an old per-connection secret returns 401.

## Implemented scope and verification

## Order import

After authorization (and after **Test connection**), `ShopifyOrdersSyncJob` runs for the connection. `ShopifyOrderSync` registers an `ORDERS_CREATE` webhook subscription pointing at `/webhooks/store_orders/:token` (rechecked at most daily) and polls recent orders. Shopify signs those deliveries with the shared app secret (`SHOPIFY_CLIENT_SECRET`); the same endpoint verifies them.

The poll runs every 10 minutes (`SHOPIFY_SYNC_CRON`, `config/schedule.yml`, or `bin/rails morea:shopify:sync` from an external cron when `SENDIT_EXTERNAL_CRON` disables the in-process schedule). The first run looks back 7 days; later runs resume from the previous run with a 5-minute overlap. It asks Shopify only for orders with `financial_status:pending` and `fulfillment_status:unfulfilled`, at most 200 orders per run, and resumes from the last handled order when it hits that cap.

Polled orders are converted to the webhook's JSON shape and pass through the same `OrderNormalizer` and receipt-backed intake as webhook deliveries, keyed by Shopify's numeric order ID, so an order delivered by both paths is imported once. The existing acceptance rules are unchanged: Cash on Delivery payment, MAD, Morocco shipping address, no tax or discounts, nothing fulfilled or cancelled. Anything else is kept as a **rejected** receipt with its reason on the connection page rather than imported. Imported orders arrive as **New** and follow the normal confirmation flow; importing never confirms, ships, edits or cancels anything in Shopify.

Protected customer fields (name, phone, address) are returned only if the app has Shopify's protected customer data approval; without it, orders are rejected as incomplete. Products, customers and inventory are not imported; order lines are snapshots by name, variant title, quantity and price.

Use the isolated test database setup from `spec/README.md`. Request tests cover tenant boundaries, forged/stale/replayed callbacks, encrypted-token UI privacy and configuration errors; service tests use synthetic HTTP responses and exercise token refresh, permission checks and safe failures. No live Shopify installation or production write is used in executable verification. Production onboarding still requires app credentials, registered callback/distribution settings, data-access approval and a sandbox installation.

The migration is additive, retains existing webhook credentials and loosens their null constraint for API connections. Preserve the new columns on code rollback. Rolling the migration down removes OAuth state/tokens and requires API-only rows with null webhook credentials to be handled before restoring the old not-null constraint.
