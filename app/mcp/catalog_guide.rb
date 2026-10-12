# frozen_string_literal: true

class CatalogGuide
  TEXT = <<~MD.freeze
    # Morea catalog

    You are connected to one store. Sign-in or the Bearer token already selected it. Do not ask for a store id, and do not query another store.

    Prefer the MCP tools. This manual is the resource `morea://catalog` and the GraphQL query `{ guide }`.
    GraphQL is `POST /graphql` on this host with `Authorization: Bearer <token>`, `Content-Type: application/json`, and body `{ "query": "...", "variables": {} }`.

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

    - `store_stats`, `product_stats`, `list_orders`, `get_order`. Read only. `since` and `until` are `YYYY-MM-DD`. They default to the last 30 days and cannot span more than 366 days. Order lists are not date-filtered unless you pass a date.
    - Placed numbers use `created_at`. Delivered numbers use `delivered_at` and are the cash collected. Cancel and return rates are among orders placed in the window.
    - `pipeline` is how many orders are in each status right now, including `address_issue`, `unreachable`, and `postponed`.
    - Money is whole currency units (`revenueDh`), same as `priceDh`.
    - Orders include city, district, totals, Sendit status, and line items. They do not include phone, street address, or email.
    - Product stock in stats is the sellable stock: variant stock when variants exist, otherwise the product stock. `lowStock` uses the store threshold.

    ## MCP tools

    Products: `list_products` (`query`, `status`, `limit` 1–100, default 50), `get_product`, `create_product`, `update_product`, `delete_product`, `set_product_collections`, `set_product_variants`, `delete_product_variants`.

    Analytics: `store_stats`, `product_stats` (`slug` optional), `list_orders` (`status`, `city`, `since`, `until`, `limit`), `get_order` (`number`).

    Collections: `list_collections` (`published`, `limit`), `get_collection`, `create_collection`, `update_collection`, `delete_collection`, `set_collection_products`.

    Images: `add_product_images`, `remove_product_images`, `reorder_product_images`, `set_collection_image`, `remove_collection_image`.

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
  MD

  def self.text
    TEXT
  end
end
