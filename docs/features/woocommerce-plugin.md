# Seallo Connect for WooCommerce plugin

The WordPress plugin sets up the WooCommerce side of the [signed order intake](connected-store-contracts.md) for the merchant. It creates and maintains one native WooCommerce webhook (`order.created`, REST API v3 payload, active) that delivers to a connection's `POST /webhooks/store_orders/:token` endpoint. It adds no order logic, signing code or API client: WooCommerce itself signs the raw body (Base64 HMAC-SHA256 in `X-WC-Webhook-Signature`) and sets `X-WC-Webhook-Topic` and `X-WC-Webhook-Source`, which `Connections::WebhookIntake` already verifies. Every intake rule, order restriction and failure code in the connected-store contract is unchanged.

Source: [merouaneamqor/seallo-connect-woocommerce](https://github.com/merouaneamqor/seallo-connect-woocommerce) (private). Current release: `v0.1.0`, a pre-release that has not yet been run against a live WordPress and WooCommerce site.

## Requirements

WordPress 6.4+, PHP 7.4+, WooCommerce 8.0+. The store must be served over HTTPS: intake accepts a WooCommerce delivery only when `X-WC-Webhook-Source` is an HTTPS URL whose hostname equals the connection's configured hostname. The plugin declares compatibility with WooCommerce's custom order tables.

## Install and connect

1. In Morea, open **Admin → Connected stores** and create a WooCommerce connection with the bare store hostname and a signing secret, as described in the connected-store contract. Copy the connection's endpoint.
2. In WordPress, open **Plugins → Add New → Upload Plugin** and upload `seallo-connect-woocommerce-<version>.zip` from the GitHub release assets, then activate it. WooCommerce must already be active.
3. Open **WooCommerce → Seallo Connect**. Paste the endpoint and the same signing secret and choose **Connect**. The endpoint must be HTTPS and contain `/webhooks/store_orders/`; the first connection requires a secret.
4. Place a sandbox cash-on-delivery order. The Morea connection stays **configured** until the first valid signed delivery arrives, then shows verified. Do not enable production traffic before this check.

The signing secret is never shown again after saving. To rotate it, enter the new secret in both Morea and the plugin; leaving the plugin field blank keeps the current secret.

## Behavior

- Saving updates the same webhook (its ID is kept in the `seallo_wc_webhook_id` option), so there is never more than one.
- The settings page shows the webhook's WooCommerce status and failure count. WooCommerce disables a webhook after repeated failed deliveries; re-save the settings page to reactivate it once the cause is fixed.
- **Deactivating** the plugin pauses the webhook. Reactivating the plugin and saving resumes delivery with the same secret.
- **Disconnect**, and uninstalling the plugin, delete the webhook and the plugin's options. Disconnecting in WordPress does not disconnect the Morea connection: deliveries simply stop. Disconnect the connection in Morea separately if it is no longer wanted; it then answers any later delivery with 410 and keeps receipts and orders.
- The plugin does not filter orders. Orders outside the supported contract (paid or non-COD, non-MAD, non-Moroccan, with tax, discounts or fees) are sent, rejected by Morea with a safe error code and recorded as rejected receipts. Retry from WooCommerce's webhook delivery tools after correcting the order.

## Limits and open work

- No historical backfill, polling, outbound order update or inventory sync, matching the connected-store contract.
- No automated tests, local development environment or translations yet. The plugin was written from the WooCommerce webhook API and has not been executed.
- The repository and its releases are private, so installing needs access to the repository. A public distribution (for example wordpress.org) needs a separate decision about licensing, naming and support.

## Releasing a new version

Bump `Version` in `seallo-connect-woocommerce.php` and `SEALLO_WC_VERSION`, commit, then build the archive from the committed tree so the zip contains a single top-level `seallo-connect-woocommerce/` folder and no repository files:

```sh
git archive --format=zip --prefix=seallo-connect-woocommerce/ -o seallo-connect-woocommerce-<version>.zip HEAD
gh release create v<version> seallo-connect-woocommerce-<version>.zip --target main
```
