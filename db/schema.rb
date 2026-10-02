# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_02_190000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "city", null: false
    t.string "line1", null: false
    t.string "line2"
    t.boolean "default", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_addresses_on_customer_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["product_id"], name: "index_cart_items_on_product_id"
    t.index ["product_variant_id"], name: "index_cart_items_on_product_variant_id"
  end

  create_table "carts", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_carts_on_store_id"
    t.index ["token"], name: "index_carts_on_token", unique: true
  end

  create_table "collection_products", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.bigint "product_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "product_id"], name: "index_collection_products_on_collection_id_and_product_id", unique: true
    t.index ["collection_id"], name: "index_collection_products_on_collection_id"
    t.index ["product_id"], name: "index_collection_products_on_product_id"
  end

  create_table "collection_translations", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.string "locale", null: false
    t.string "name"
    t.string "subtitle"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "locale"], name: "index_collection_translations_on_collection_id_and_locale", unique: true
    t.index ["collection_id"], name: "index_collection_translations_on_collection_id"
  end

  create_table "collections", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "subtitle"
    t.text "description"
    t.boolean "published", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "slug"], name: "index_collections_on_store_id_and_slug", unique: true
    t.index ["store_id"], name: "index_collections_on_store_id"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "name", null: false
    t.string "phone", null: false
    t.string "email"
    t.string "city"
    t.integer "orders_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "phone"], name: "index_customers_on_store_id_and_phone", unique: true
    t.index ["store_id"], name: "index_customers_on_store_id"
  end

  create_table "discounts", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "code", null: false
    t.string "discount_type", default: "percent", null: false
    t.integer "value", null: false
    t.boolean "active", default: true, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "code"], name: "index_discounts_on_store_id_and_code", unique: true
    t.index ["store_id"], name: "index_discounts_on_store_id"
  end

  create_table "home_section_translations", force: :cascade do |t|
    t.bigint "home_section_id", null: false
    t.string "locale", null: false
    t.string "heading"
    t.string "subheading"
    t.text "body"
    t.string "button_label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["home_section_id", "locale"], name: "index_home_section_translations_on_home_section_id_and_locale", unique: true
    t.index ["home_section_id"], name: "index_home_section_translations_on_home_section_id"
  end

  create_table "home_sections", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.boolean "visible", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "position"], name: "index_home_sections_on_store_id_and_position"
    t.index ["store_id"], name: "index_home_sections_on_store_id"
  end

  create_table "inventory_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.bigint "order_id"
    t.integer "quantity", null: false
    t.string "reason", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_inventory_movements_on_order_id"
    t.index ["product_id"], name: "index_inventory_movements_on_product_id"
    t.index ["product_variant_id"], name: "index_inventory_movements_on_product_variant_id"
  end

  create_table "menu_item_translations", force: :cascade do |t|
    t.bigint "menu_item_id", null: false
    t.string "locale", null: false
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id", "locale"], name: "index_menu_item_translations_on_menu_item_id_and_locale", unique: true
    t.index ["menu_item_id"], name: "index_menu_item_translations_on_menu_item_id"
  end

  create_table "menu_items", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "menu", null: false
    t.integer "position", default: 0, null: false
    t.string "link", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "menu", "position"], name: "index_menu_items_on_store_id_and_menu_and_position"
    t.index ["store_id"], name: "index_menu_items_on_store_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.string "product_name", null: false
    t.string "variant_name"
    t.integer "quantity", null: false
    t.integer "unit_price_cents", null: false
    t.integer "total_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.index ["product_variant_id"], name: "index_order_items_on_product_variant_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "customer_id", null: false
    t.string "number", null: false
    t.string "status", default: "new", null: false
    t.string "payment_method", default: "cod", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "shipping_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.string "currency", default: "DH", null: false
    t.string "customer_name", null: false
    t.string "customer_phone", null: false
    t.string "customer_city", null: false
    t.string "customer_address", null: false
    t.text "notes"
    t.datetime "confirmed_at"
    t.datetime "shipped_at"
    t.datetime "delivered_at"
    t.datetime "cancelled_at"
    t.string "cancel_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sendit_code"
    t.string "sendit_status"
    t.integer "sendit_district_id"
    t.string "sendit_district_name"
    t.decimal "sendit_fee", precision: 10, scale: 2
    t.string "sendit_message"
    t.date "sendit_deliver_by"
    t.text "sendit_error"
    t.datetime "sendit_synced_at"
    t.string "sendit_return_status"
    t.datetime "returned_at"
    t.string "customer_district"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["customer_phone"], name: "index_orders_on_customer_phone"
    t.index ["number"], name: "index_orders_on_number", unique: true
    t.index ["sendit_code"], name: "index_orders_on_sendit_code", unique: true
    t.index ["status"], name: "index_orders_on_status"
    t.index ["store_id"], name: "index_orders_on_store_id"
  end

  create_table "page_translations", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.string "locale", null: false
    t.string "title"
    t.text "body"
    t.string "seo_title"
    t.string "seo_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id", "locale"], name: "index_page_translations_on_page_id_and_locale", unique: true
    t.index ["page_id"], name: "index_page_translations_on_page_id"
  end

  create_table "pages", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "slug", null: false
    t.boolean "published", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "slug"], name: "index_pages_on_store_id_and_slug", unique: true
    t.index ["store_id"], name: "index_pages_on_store_id"
  end

  create_table "product_translations", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "locale", null: false
    t.string "name"
    t.text "short_description"
    t.text "story"
    t.text "material"
    t.text "fit"
    t.text "movement"
    t.text "dimensions"
    t.string "origin"
    t.text "care"
    t.string "seo_title"
    t.string "seo_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "locale"], name: "index_product_translations_on_product_id_and_locale", unique: true
    t.index ["product_id"], name: "index_product_translations_on_product_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.string "sku"
    t.string "option1_name"
    t.string "option1_value"
    t.string "option2_name"
    t.string "option2_value"
    t.integer "price_cents"
    t.integer "stock", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.integer "price_cents", null: false
    t.integer "compare_at_cents"
    t.string "currency", default: "DH", null: false
    t.text "short_description"
    t.text "story"
    t.text "material"
    t.text "dimensions"
    t.string "origin"
    t.text "care"
    t.string "sku"
    t.integer "stock", default: 0, null: false
    t.boolean "track_inventory", default: true, null: false
    t.boolean "featured", default: false, null: false
    t.integer "position", default: 0, null: false
    t.string "seo_title"
    t.string "seo_description"
    t.string "image_url"
    t.string "detail_image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "fit"
    t.text "movement"
    t.integer "image_order", default: [], null: false, array: true
    t.index ["featured"], name: "index_products_on_featured"
    t.index ["status"], name: "index_products_on_status"
    t.index ["store_id", "slug"], name: "index_products_on_store_id_and_slug", unique: true
    t.index ["store_id"], name: "index_products_on_store_id"
  end

  create_table "store_translations", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "locale", null: false
    t.string "tagline"
    t.text "about"
    t.string "cod_label"
    t.text "cod_note"
    t.string "campaign_title"
    t.string "campaign_season"
    t.string "campaign_cta"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "announcement"
    t.index ["store_id", "locale"], name: "index_store_translations_on_store_id_and_locale", unique: true
    t.index ["store_id"], name: "index_store_translations_on_store_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "tagline"
    t.text "about"
    t.string "phone"
    t.string "email"
    t.string "currency", default: "DH", null: false
    t.string "cod_label", default: "Cash on delivery"
    t.text "cod_note"
    t.bigint "featured_product_id"
    t.bigint "featured_collection_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "campaign_title"
    t.string "campaign_season"
    t.string "campaign_image_url"
    t.string "campaign_cta"
    t.integer "sendit_pickup_district_id"
    t.string "whatsapp"
    t.index ["slug"], name: "index_stores_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name"
    t.boolean "admin", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "customers"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "product_variants"
  add_foreign_key "cart_items", "products"
  add_foreign_key "carts", "stores"
  add_foreign_key "collection_products", "collections"
  add_foreign_key "collection_products", "products"
  add_foreign_key "collection_translations", "collections"
  add_foreign_key "collections", "stores"
  add_foreign_key "customers", "stores"
  add_foreign_key "discounts", "stores"
  add_foreign_key "home_section_translations", "home_sections"
  add_foreign_key "home_sections", "stores"
  add_foreign_key "inventory_movements", "orders"
  add_foreign_key "inventory_movements", "product_variants"
  add_foreign_key "inventory_movements", "products"
  add_foreign_key "menu_item_translations", "menu_items"
  add_foreign_key "menu_items", "stores"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "stores"
  add_foreign_key "page_translations", "pages"
  add_foreign_key "pages", "stores"
  add_foreign_key "product_translations", "products"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "stores"
  add_foreign_key "store_translations", "stores"
end
