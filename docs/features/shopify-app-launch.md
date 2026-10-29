# Launching the Seallo Shopify app

Seallo uses Morea's Rails admin as a standalone Shopify app. The app entry URL is `/admin/shopify`; Shopify approval returns to `/admin/shopify/callback`. Each client signs into their Morea workspace and explicitly connects their permanent `*.myshopify.com` domain. The authenticated workspace owns the connection; a Shopify URL parameter never selects a Morea tenant or grants access.

The existing integration imports eligible Moroccan COD orders into Morea. It does not synchronize products, stock, fulfillment, payment or order edits back to Shopify. See [connection and intake contracts](shopify-api-connection.md) for acceptance rules and polling behavior.

## Distribution and current release blockers

Use **public distribution** for one shared app installed by unrelated client businesses. Shopify requires review. Custom distribution is limited to a single store, development stores, or stores in one Plus organization; it is not a way to distribute this shared app to unrelated clients. The distribution method cannot be changed after selection. Use separate development and production app records. See [Shopify distribution](https://shopify.dev/docs/apps/launch/distribution).

This checkout is an installation foundation, not an approved public app. Before public review, implement and register `customers/data_request`, `customers/redact` and `shop/redact`. These need verified delivery, durable processing, tenant-scoped export/redaction, retries and an explicit retention policy covering imported orders, receipt payloads, backups and accounting obligations. An uninstall notification alone does not perform these duties. Invalid compliance HMACs must return HTTP 401. The template intentionally omits nonexistent compliance endpoints. See [Shopify privacy webhook requirements](https://shopify.dev/docs/apps/build/compliance/privacy-law-compliance).

Order names, shipping addresses and phone numbers need the applicable protected customer data access. Request only fields required for COD operations and supply the associated security/privacy evidence. Scopes alone do not grant these fields; redacted fields or GraphQL errors can prevent import. See [protected customer data](https://shopify.dev/docs/apps/launch/protected-customer-data).

## Configure the app

1. Create the development app in Shopify Dev Dashboard. Keep its client secret in the Rails deployment's secret settings. Never put it in TOML, source, screenshots or client instructions.
2. Copy `shopify.app.toml.example` to your selected Shopify configuration file and replace its public client ID. For production, use `https://ollazen.com/admin/shopify` as the application URL and exactly `https://ollazen.com/admin/shopify/callback` as an allowed redirect URL.
3. Keep `embedded = false` and `use_legacy_install_flow = true`: the current Rails code sends scopes in its authorization-code grant. Switching to managed installation or an embedded app requires a coordinated authentication change. The legacy flag remains supported but Shopify recommends managed installation for new implementations. See [app configuration](https://shopify.dev/docs/apps/build/cli-for-apps/app-configuration).
4. Configure `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` on both Rails web and worker processes. Keep `SECRET_KEY_BASE` stable: existing connection tokens are encrypted using it. Confirm the normal Sidekiq worker and Shopify polling schedule are running.
5. Preserve current scopes `write_orders,read_orders,read_customers,read_products` until the authorization constants, verifier and tests change together. Audit least privilege before review: the current importer reads order snapshots and does not implement product sync or Shopify order writes. Do not remove a scope only from TOML while the verifier still requires it.
6. Register the `app/uninstalled` subscription from the template. `orders/create` is already registered by the existing sync service with a connection-specific endpoint; adding an app-wide duplicate does not replace that contract.

Shopify CLI can link an existing app with `shopify app config link`; it can overwrite configuration, so review the resulting file against the template. Run `shopify app config validate` after replacing placeholders. `shopify app deploy` releases Shopify configuration/extensions; deploy the Rails application separately through its normal hosting workflow. Confirm the selected app and environment before any release. The [CLI command reference](https://shopify.dev/docs/api/shopify-cli/app) describes linking, validation and deployment.

## Verify on a development store

Use a separate Morea test deployment, synthetic workspace and Shopify development store. Set `APP_BASE_DOMAIN` to that deployment's HTTPS host and omit `APP_PORT` for standard HTTPS. The app URL, OAuth callback and generated order webhook URL must all refer to this environment. Configure the development app's client ID/secret there; production credentials must remain separate. Select the app's distribution method and enable its required protected data fields in the dashboard; development-store-only access does not require submitting the public data review. A development installation exercises real Shopify APIs, so use synthetic orders only.

1. Open the app entry URL signed out, sign in as the synthetic workspace administrator, and confirm the connection page opens. Test both a new and an existing connection. Confirmation agents and platform-only sessions must not gain workspace access.
2. Connect the development store, approve Shopify access, and return to the same workspace. Confirm the shop identity and required scopes, then run **Test connection**. Check the UI does not expose tokens or the shared secret.
3. Create an unpaid, unfulfilled COD order in MAD with a Moroccan shipping address, synthetic name/phone/address and no tax or discounts. Confirm it appears once as **New**. Deliver the same order through polling/webhook replay and confirm no duplicate. Verify unsupported orders produce rejected receipts with a reason.
4. Uninstall Seallo in the development store. Confirm the connection stops importing, local OAuth credentials and pending authorization are cleared, and existing Morea orders remain. Reinstall and explicitly authorize again; confirm webhook registration and import resume.
5. Check English, French and Arabic admin pages, including RTL. Check a second synthetic tenant cannot view, authorize or test the first tenant's connection. Public storefronts and disabled-storefront behavior must remain unchanged.

Run local automated specs only with `RAILS_ENV=test` and a dedicated test database, following [spec setup](../../spec/README.md). Passing disconnected specs does not establish that a live development-store installation, protected customer field access, production deployment or Shopify review has succeeded.

Uninstall processing is idempotent and retains imported orders and receipt history. Shopify may deliver an uninstall late, including after a reinstall; in that case reconnect and authorize again. Delivery timestamps are not signed with the body and cannot safely identify an installation generation. Uninstall is a credential cleanup operation; it does not replace the required privacy workflow.

## Before onboarding clients

Finish the privacy workflow and register all three mandatory compliance subscriptions, complete the scope/data-access review, publish the app's merchant privacy/support information, and perform the development-store acceptance flow. Then prepare the public listing and review credentials with synthetic data. Keep Shopify approval, configuration release, Rails deployment and a verified client installation as separate milestones.

## Existing Render service

Deploy the Rails changes to the existing `morea` service before changing the Shopify App URL to `https://ollazen.com/admin/shopify`. Keep the exact allowed OAuth redirect `https://ollazen.com/admin/shopify/callback`, disable embedding, retain the four configured scopes and release the Shopify configuration version. The uninstall subscription must target `https://ollazen.com/webhooks/shopify/uninstalled`.

Set the shared app's `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` in the Render service environment. Inspect existing app configuration before replacing it: changing a shared app's credentials can break other shops' connections. Keep the existing `SECRET_KEY_BASE`, database and Redis settings. Never copy the sandbox's database URL, encryption key or encrypted tokens into production. The client must sign in to their authorized Morea workspace on the permanent host and complete OAuth there again; sandbox cookies and connections do not transfer.

`bin/render-start.sh` already starts Sidekiq alongside Puma. Shopify's default schedule is every 10 minutes. `SENDIT_EXTERNAL_CRON` disables only Sendit polling; set `SHOPIFY_EXTERNAL_CRON` only when a separate scheduler actually runs `bin/rails morea:shopify:sync`. Verify the worker is consuming `default`, the schedule is enabled, authorization succeeds, the order subscription points to the permanent host, and an eligible synthetic order enters the chosen test workspace once.

A Render Free web service sleeps after 15 minutes without inbound traffic, which also stops its colocated Sidekiq scheduler. Webhooks can experience cold-start delays and polling cannot run while the service sleeps. Reliable continuous processing needs an approved always-running service/worker or an external scheduler. Do not change paid plans or add billed services implicitly. See [Render Free limitations](https://render.com/docs/free).

After verifying the new connection, disable the local sandbox connection and remove its old Shopify order subscription using the authorized app API. This prevents the temporary tunnel from remaining an active destination. Preserve existing order/receipt history in both environments, and keep the test app limited to development-store testing until public launch requirements are complete.
