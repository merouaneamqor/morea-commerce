# Connected stores: signed order intake

Shopify now uses the shared Seallo app's [OAuth API connection](shopify-api-connection.md). Its admin setup contains no webhook instructions, signing-secret field or delivery URL. Existing imported orders remain available. Automatic API import and synchronization are not enabled by connecting the API.

WooCommerce and YouCan retain signed order intake without local catalog products. Storefront visibility is a separate setting; existing Codify checkout remains available when enabled. These two platforms use manual webhook setup. There is no remote subscription creation, historical backfill, polling, outbound order update or inventory synchronization.

## Provider setup and verified evidence

Create a WooCommerce or YouCan connection under **Admin → Connected stores**. Enter a descriptive name, bare provider hostname and signing secret. YouCan also requires the external store UUID. Keep signing secrets private. Codify stores secrets as authenticated AES-256-GCM ciphertext using a key derived from the existing stable Rails `secret_key_base`; deployment needs no additional encryption variables. Rotating that base key requires re-entering connection secrets before deliveries can resume.

The connection form starts with a platform choice and shows only the relevant fields in English, French and Arabic. Existing legacy Shopify webhook records are retained for compatibility and are not offered as a new setup option. A validated OAuth callback switches the connection to API mode before token exchange; the connection then receives orders through the shared app's webhook and polling (see `shopify-api-connection.md`), and deliveries signed with a legacy per-connection secret are rejected with 401. Complete authorization if token exchange fails. Existing orders and receipt identities are retained. Remove any old provider subscription after switching.

Copy the connection endpoint into the provider's webhook subscription:

| Provider | Subscription | Secret | Verification |
| --- | --- | --- | --- |
| Shopify (legacy only) | `orders/create` | App client secret for the subscribed app | Base64 HMAC-SHA256 of raw body in `X-Shopify-Hmac-SHA256`; exact `X-Shopify-Shop-Domain` match |
| WooCommerce | `order.created`, REST API v3 payload | Explicit webhook secret | Base64 HMAC-SHA256 of raw body in `X-WC-Webhook-Signature`; HTTPS `X-WC-Webhook-Source` hostname match |
| YouCan | `order.created`, API `v1` | Subscribing OAuth client's secret | Lowercase hex HMAC-SHA256 of raw body in `X-YOUCAN-SIGNATURE`; envelope `data.store_id` matches configured store UUID |

The endpoint is `POST /webhooks/store_orders/:token`. Its opaque token selects a connection; signatures authenticate deliveries. A body-supplied Codify `store_id` is never used. Configuring a connection shows **configured** until a valid signed source delivery is received. Disconnecting rejects subsequent deliveries with 410 and preserves receipts/orders. Provider-side subscriptions must be removed or reactivated in that provider's dashboard as appropriate. WooCommerce's unsigned form activation probe (`webhook_id=<integer>`) is acknowledged without importing, recording or verifying anything.

Provider contracts checked against official documentation on 24 October 2026:

- [Shopify delivery verification](https://shopify.dev/docs/apps/build/webhooks/verify-deliveries) and [order webhook headers](https://shopify.dev/docs/agents/orders/order-webhooks).
- [WooCommerce v3 webhooks](https://developer.woocommerce.com/docs/apis/rest-api/v3/webhooks/) and [official WC_Webhook source, including activation ping](https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/includes/class-wc-webhook.php).
- [YouCan REST Hooks envelope, headers and signature](https://docs.youcan.shop/store-admin/resthooks/overview), [order entity](https://docs.youcan.shop/store-admin/entities/order), [full order relationships](https://docs.youcan.shop/store-admin/orders/get), and [address fields](https://docs.youcan.shop/store-admin/orders/create).

YouCan documentation confirms the envelope and signing format but shows only a trimmed webhook example. Codify requires expanded payment, shipping/address and variants/product relationships as documented by the full order resource. Missing relationships produce `incomplete_payload`, with no order created. This slice does not fetch missing relationships with a provider token. Real provider onboarding still needs a sandbox delivery to establish that those relationships are present; synthetic checks are not proof of live payload completeness.

## Supported order contract

Only new, unpaid cash-on-delivery orders in MAD (including a local store's DH display alias), delivered to a Moroccan address, enter the existing order queue. Shopify's gateway must be exactly `Cash on Delivery (COD)` and financial status `pending`; WooCommerce uses gateway `cod` without a paid date; YouCan uses documented gateway type 1 and pending payment status. Non-COD and paid orders are rejected to avoid charging a customer twice. Shipped, cancelled and refunded orders are unsupported.

Prices and totals are preserved as integer cents using decimal arithmetic. Tax, discounts and WooCommerce fees are unsupported in this slice. Amount precision beyond cents, overflow, missing contact/line fields, fractional quantities and totals that do not reconcile exactly are rejected. Codify's shipping defaults and catalog prices never replace source amounts.

Lines are immutable commercial snapshots with no local product/variant mapping. Selected variants are preserved in a bounded text label: Shopify's variant title, public WooCommerce option metadata, or YouCan variations/options/values. WooCommerce underscore-prefixed private metadata is excluded, and option HTML is stripped. If option labels are missing, WooCommerce's variation ID or YouCan's variant ID remains visible for fulfillment. Receiving and confirming these orders does not change local stock. Existing confirmation, shipment and cancellation workflows operate on the order; no notification, shipment or job is triggered by receipt itself. Catalog mapping and provider stock changes need a later explicit contract.

## Replay, failure and privacy

The durable identity is `(store_connection_id, external_id)` with a database unique index. Connection and tenant locks serialize competing receipts/customer updates. Order, snapshot lines, customer count and successful receipt commit atomically. An accepted replay returns the original order and ignores altered payload data. An authenticated rejected receipt can be retried with corrected provider data. Different connections have separate identities, even if the provider's order IDs overlap.

Accepted deliveries return 200. Authenticated order validation failures return 422, preserve a receipt with external ID and a safe error code, and update the connection's last error. Invalid signatures return 401, wrong source 403, missing connection 404, disconnected connection 410, oversized body 413, invalid JSON/topic/identity 422, and unavailable decryption key 503. Authentication/source failures do not persist untrusted receipt identities. Requests are capped at 1 MiB. Unexpected database errors remain retryable server errors.

Raw payloads, credentials and provider responses are not stored in receipts or events. Customer contact is stored only in normal customer/order records after acceptance. Receipt history contains only the source order ID, timestamps, status, order association and safe error code. Retry from the provider's delivery tools; there is no Codify payload replay button because raw payloads are not retained. Provider retry/deactivation policy can stop subscriptions after repeated errors, so fix rejected orders and inspect delivery history promptly.

## Verification and rollback

Run on an isolated migrated test database:

```sh
RAILS_ENV=test bin/rails runner script/connected_store_intake_smoke.rb
```

The script covers synthetic signatures for all three providers, exact cents, missing signatures, source isolation, disconnects, rejected-delivery correction, accepted replay, concurrency, no import jobs, nil-product confirmation/cancellation and two tenants. Controller/admin acceptance is covered separately by the connected-store admin smoke script. No real provider is called. Deployment verification must include a disconnected sandbox setup before enabling production deliveries.

Migrations are additive. Rolling them down deletes connection credentials and receipt identities/history; received normal orders are retained. Preserve tables on a code rollback until duplicate-intake implications and retention requirements have been reviewed.
