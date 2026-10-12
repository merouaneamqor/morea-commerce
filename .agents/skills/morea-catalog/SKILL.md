---
name: morea-catalog
description: Operate one Morea store through its remote MCP: catalog, variants, cover photos, delivery orders, cash on delivery checkout, Sendit shipping, coupons, customers, CSV, pixels, and the home page. Use when the user mentions Morea, ollazen.com, a store catalog, COD, discounts, customers, shipping, or connecting an agent to a store.
---

# Morea catalog

You are connected to one store. Sign-in or the Bearer token already selected it. Do not ask for a store id, and do not query another store.

Prefer the MCP tools. This manual is the resource `morea://catalog`, the GraphQL query `{ guide }`, and the installable skill `morea-catalog`.

## Install

Agents install this skill from the store host, not from the apex `ollazen.com`:

```bash
npx skills add https://<store>.ollazen.com
```

The same file is `GET /.well-known/agent-skills/morea-catalog/SKILL.md`. Discovery is `GET /.well-known/agent-skills/index.json`.

## Connect

MCP URL: `https://<store>.ollazen.com/mcp`. Example: `https://morea.ollazen.com/mcp`.

The agent signs in on that store. If it asks for a header instead of a login, use `Authorization: Bearer <token>` from the store's Agent API page. A token from another host does not work.

GraphQL is `POST /graphql` on this host with the same Bearer token, `Content-Type: application/json`, and body `{ "query": "...", "variables": {} }`.

If `list_orders` or `get_order` is missing, that chat kept an older tool list. Open a new chat and connect again. Those tools are on the server.

## Store

Cash on delivery is the only payment gateway. `get_store_settings` and `update_checkout` set the COD label, contact details, fallback shipping price, and free-shipping threshold. Card gateways are not available.

Sendit is the shipping provider. `update_shipping` sets the API keys, pickup district, and Discord order webhook. Blank secrets stay unchanged. `sync_shipping` with `confirm: true` queues a refresh of open parcels.

Coupons: `list_discounts`, `upsert_discount`, `delete_discount`. `discountType` is `percent` or `fixed`.

`list_abandoned_carts` shows carts that still have items. Those carts have no phone or email, so there is no recovery message to send.

Customers: `list_customers`, `get_customer`, `upsert_customer`. These include phone and email. Order tools still leave phone, street address, and email out.

Marketing tags are `update_marketing` (Meta and TikTok pixel ids). There is no email campaign.

`export_csv` and `import_csv` cover products, customers, and discounts. Export also covers orders, without phone or street address. Import needs `confirm: true`.

The home page is `list_home_sections`, `upsert_home_section`, and `delete_home_section`. Pages and header/footer links have the same list, upsert, and delete tools. `install_theme` fills only the parts that are still empty. The public host is the store subdomain. Custom domains are not a setting.

## Rules

- Prices are whole currency units in `priceDh` (120 means 120 DH), not cents.
- Locales are `fr`, `en`, and `ar`. Create a product or collection with a `fr` translation `name`. Other locales are optional.
- On update, omit a field to leave it unchanged. `newSlug` renames. `clearCompareAt: true` removes the compare-at price. An empty `sku` clears the SKU.
- `delete_product` and `delete_collection` do nothing unless `confirm` is true. A product that is already on an order cannot be deleted.
- Slugs are unique per store. Unknown slugs come back in `errors`.
- Status is `draft`, `active`, or `archived`. New products default to `draft`.
- `set_product_collections` and `set_collection_products` replace the full membership. Pass `[]` to clear it. Order of `productSlugs` is the collection order.
- Variants are size and color. `set_product_variants` upserts by that pair; omit a row to leave it. `delete_product_variants` needs `confirm: true`. A blank `priceDh` uses the product price.
- When a product has variants, the storefront sells the sum of active variant stock. Change that stock, not the product `stock` field.
- Inventory movements are not available here.

## Images

- `coverUrl` is the photo shown on the store. Display that image. Do not search the web or substitute another photo.
- A collection with no uploaded cover uses its first product photo as `coverUrl`. `image` is null in that case; that is not a missing product photo.
- Product `images` are the gallery in storefront order. Position 0 is the cover. Later images are alternate shots, not replacements for the cover.
- Returned image URLs are JPEG. Tool results also include the cover bytes.
- Product images: `add_product_images`, `remove_product_images`, `reorder_product_images`.
- Collection cover: `set_collection_image`, `remove_collection_image`.
- Each image is `base64` (raw or a `data:` URL) or a public `http`/`https` `url`. Also pass `filename` and `contentType` when you have them.
- Allowed types: `image/jpeg`, `image/png`, `image/webp`, `image/gif`. Max 8MB. Max 4 images per call.
- Private, loopback, and link-local URLs are rejected.
- New product images are appended. `reorder_product_images` takes attachment ids; the first id is the cover. Ids you omit stay after the ones you list.
- Remove images by the `id` returned on `images` / `image`.

## Analytics

- `store_stats`, `product_stats`, `list_orders`, `get_order` are read only. `cancel_order` cancels one order by `number` and needs `confirm: true`. An optional `reason` is stored on the order. Cancel works from `new`, `confirmed`, `preparing`, `awaiting_pickup`, and `address_issue`. It restores reserved stock and deletes a Sendit parcel that has not left the warehouse. After pickup, say the order cannot be cancelled from its current status.
- `since` and `until` are `YYYY-MM-DD`. They default to the last 30 days and cannot span more than 366 days. Order lists are not date-filtered unless you pass a date.
- Placed numbers use `created_at`. Delivered numbers use `delivered_at` and are the cash collected. Cancel and return rates are among orders placed in the window.
- `pipeline` is how many orders are in each status right now, including `address_issue`, `unreachable`, and `postponed`.
- Money is whole currency units (`revenueDh`), same as `priceDh`.
- Orders include number, status, dates, city, district, totals, discount code, notes, Sendit (code, status, fee, deliver-by, error), and lines (slug, name, variant, quantity, prices). They do not include phone, street address, or email.
- Product stock in stats is the sellable stock: variant stock when variants exist, otherwise the product stock. `lowStock` uses the store threshold.
- Do not invent order numbers, cities, or totals. If `list_orders` is not in the tool list, say so and ask for a new chat.

## MCP tools

Products: `list_products` (`query`, `status`, `limit` 1–100, default 50), `get_product`, `create_product`, `update_product`, `delete_product`, `set_product_collections`, `set_product_variants`, `delete_product_variants`.

Analytics: `store_stats`, `product_stats` (`slug` optional), `list_orders` (`status`, `city`, `since`, `until`, `limit`), `get_order` (`number`), `cancel_order` (`number`, `confirm`, `reason`).

Collections: `list_collections` (`published`, `limit`), `get_collection`, `create_collection`, `update_collection`, `delete_collection`, `set_collection_products`.

Images: `add_product_images`, `remove_product_images`, `reorder_product_images`, `set_collection_image`, `remove_collection_image`.

Store: `get_store_settings`, `update_checkout`, `update_marketing`, `update_shipping`, `sync_shipping`, `list_discounts`, `upsert_discount`, `delete_discount`, `list_abandoned_carts`, `list_customers`, `get_customer`, `upsert_customer`, `export_csv`, `import_csv`, `list_home_sections`, `upsert_home_section`, `delete_home_section`, `list_pages`, `upsert_page`, `delete_page`, `list_menu_items`, `upsert_menu_item`, `delete_menu_item`, `install_theme`.

Read `errors` in the tool result before assuming a write worked.

## GraphQL examples

List:

```graphql
query {
  products(query: "linen", status: "active", limit: 20) {
    slug status priceDh collectionSlugs
    images { id url position }
    translations { locale name }
  }
}
```

Create:

```graphql
mutation($priceDh: Int!, $translations: [ProductTranslationInput!]!) {
  createProduct(priceDh: $priceDh, status: "active", translations: $translations) {
    product { slug }
    errors
  }
}
```

Variables: `{ "priceDh": 120, "translations": [{ "locale": "fr", "name": "Robe lin" }] }`

Upload:

```graphql
mutation($slug: String!, $images: [ImageUploadInput!]!) {
  addProductImages(slug: $slug, images: $images) {
    product { images { id filename url position } }
    errors
  }
}
```

Delete:

```graphql
mutation { deleteProduct(slug: "robe-lin", confirm: true) { deleted errors } }
```
