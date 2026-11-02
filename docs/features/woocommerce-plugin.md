# Seallo Connect for WooCommerce plugin

The WordPress plugin connects a WooCommerce store to a workspace with an OAuth authorization-code flow (PKCE), then creates and maintains one native WooCommerce webhook (`order.created`, REST API v3 payload, active) that delivers to the new connection's `POST /webhooks/store_orders/:token` endpoint. Nothing is copied or pasted. The plugin adds no order logic or signing code: WooCommerce itself signs the raw body (Base64 HMAC-SHA256 in `X-WC-Webhook-Signature`) and sets `X-WC-Webhook-Topic` and `X-WC-Webhook-Source`, which `Connections::WebhookIntake` already verifies. Every intake rule, order restriction and failure code in the [connected-store contract](connected-store-contracts.md) is unchanged.

Source: [merouaneamqor/seallo-connect-woocommerce](https://github.com/merouaneamqor/seallo-connect-woocommerce) (private). The OAuth flow is plugin version 0.2.0. It has not yet been run against a live WordPress and WooCommerce site, and the Morea endpoints described here have not been exercised against the plugin end to end.

## Requirements

WordPress 6.4+, PHP 7.4+, WooCommerce 8.0+. The site URL and wp-admin must be HTTPS on one hostname without a port: intake accepts a WooCommerce delivery only when `X-WC-Webhook-Source` is an HTTPS URL whose hostname equals the connection's hostname, and Morea only redirects to a callback on that same hostname. The plugin declares compatibility with WooCommerce's custom order tables. Morea needs no new environment variables.

## Install and connect

1. In WordPress, open **Plugins → Add New → Upload Plugin**, upload `seallo-connect-woocommerce-<version>.zip` from the GitHub release assets and activate it. WooCommerce must already be active.
2. Open **WooCommerce → Seallo Connect**, enter the HTTPS address you use to sign in to Morea admin (a bare origin; set `SEALLO_WC_APP_URL` in `wp-config.php` to pin it) and choose **Connect to Seallo**.
3. Sign in to Morea if needed. The confirmation page names the workspace and the WooCommerce site hostname. A workspace admin (or super admin) approves.
4. Morea returns the browser to WordPress, which finishes the exchange and shows **Connected**. Place a sandbox cash-on-delivery order: the connection stays **configured** until the first valid signed delivery arrives, then shows verified.

## Authorization contract

The plugin is a public client. There is no client secret; the PKCE verifier, known only to the plugin instance that started the request, takes its place.

1. **Request.** The plugin stores a single-use `state` and a PKCE verifier in a 10-minute transient bound to the signed-in WordPress user, then sends the browser to `GET /admin/woocommerce/connect?site=…&state=…&code_challenge=…&return_to=…`. `code_challenge` is the unpadded base64url SHA-256 of the verifier (43 characters).
2. **Validation.** `site` must be a hostname. `return_to` must be exactly `https://<site>[/subdir]/wp-admin/admin-post.php?action=seallo_wc_callback`: HTTPS, default port, no credentials or fragment, host equal to `site`, no dot-only path segments, no other query. Anything else is a 400, so a code can only be delivered to the origin shown on the confirmation page. The page requires a signed-in workspace admin (`WoocommerceConnectionCode.authorized?`) and the normal subscription access check, and is `no-store`.
3. **Approval.** Minting happens only on the confirmation page's POST, so navigating to a URL never creates a code. The POST stores the SHA-256 digest of a 192-bit random code with the store, issuing user, site, challenge and a 10-minute expiry, retires that user's earlier unused codes, and redirects with `head :found` (so the code is not request-logged) to `return_to&code=…&state=…`.
4. **Exchange.** The plugin checks and deletes its state, then calls `POST /api/woocommerce/connect` (JSON `code`, `code_verifier`, `site`; rate limited to 20 per minute per IP). Under a row lock, `Connections::WoocommerceConnect` requires an unconsumed, unexpired code whose site matches, whose PKCE challenge matches the verifier (constant-time), and whose issuer is still an active admin of the store. It then creates or reactivates the `woocommerce` connection for that store and hostname, generates a 256-bit signing secret, stores it encrypted like any `webhook_secret`, consumes the code and returns `{ delivery_url, secret, workspace_name }` (`no-store`). Failures return 422 with `invalid_code`, `invalid_verifier`, `invalid_site` or `invalid_connection`; a wrong verifier or site does not consume the code.
5. **Webhook.** The plugin validates the returned URL (HTTPS, contains `/webhooks/store_orders/`) and saves the secret and URL into its WooCommerce webhook.

Re-linking an existing site (same store and hostname) reuses its connection, reactivates it, clears its verified and error state, and rotates the secret, so a manual webhook set up earlier for that hostname must be replaced by the plugin's. Connections for the same hostname in another workspace are separate.

## Behavior

- Saving updates the same webhook (its ID is kept in the `seallo_wc_webhook_id` option), so there is never more than one.
- The settings page shows the webhook's WooCommerce status and failure count. WooCommerce disables a webhook after repeated failed deliveries; **Reconnect** reactivates it once the cause is fixed.
- **Deactivating** the plugin pauses the webhook. **Disconnect** and uninstalling delete the webhook and the plugin's options. Neither disconnects the Morea connection: deliveries simply stop. Disconnect the connection under **Admin → Connected stores** too if it is no longer wanted; it then answers any later delivery with 410 and keeps receipts and orders.
- The plugin does not filter orders. Orders outside the supported contract (paid or non-COD, non-MAD, non-Moroccan, with tax, discounts or fees) are sent, rejected by Morea with a safe error code and recorded as rejected receipts. Retry from WooCommerce's webhook delivery tools after correcting the order.

## Security notes and limits

- Approval is a consent decision: the confirmation page names the site hostname and warns that anyone holding the connection's secret can submit orders to the workspace. A merchant who approves a site they do not control gives that site's owner the ability to submit supported COD orders. Morea cannot verify site ownership beyond the callback being on that hostname.
- The code travels in the browser redirect, so it is single-use, short-lived and useless without the verifier. The secret is returned only in the server-to-server response and is not shown to the merchant.
- No historical backfill, polling, outbound order update or inventory sync, matching the connected-store contract.
- Not yet covered: automated plugin tests, a local development environment, translations, and an admin-side "Connect with plugin" entry point in Morea (the connection appears under Connected stores once approved).
- The repository and its releases are private, so installing needs access to the repository. A public distribution (for example wordpress.org) needs a separate decision about licensing, naming and support.

## Verification

`spec/requests/woocommerce_connections_spec.rb` covers sign-in requirements, confirmation without minting on GET, callback validation, digest-only storage, a successful exchange, single use, wrong verifier/site/code, expiry, issuer losing access, and re-link secret rotation. It needs an isolated migrated test database and was not run when written. The migration `create_woocommerce_connection_codes` is additive; rolling it down deletes only pending codes.

## Releasing a new version

Bump `Version` in `seallo-connect-woocommerce.php` and `SEALLO_WC_VERSION`, commit, then build the archive from the committed tree so the zip contains a single top-level `seallo-connect-woocommerce/` folder and no repository files:

```sh
git archive --format=zip --prefix=seallo-connect-woocommerce/ -o seallo-connect-woocommerce-<version>.zip HEAD
gh release create v<version> seallo-connect-woocommerce-<version>.zip --target main
```
