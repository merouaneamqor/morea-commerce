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

ActiveRecord::Schema[8.1].define(version: 2026_10_24_170000) do
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

  create_table "admin_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "store_id"
    t.string "token_digest", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.string "ip"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_admin_sessions_on_store_id"
    t.index ["token_digest"], name: "index_admin_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_admin_sessions_on_user_id"
  end

  create_table "agent_changesets", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "token", null: false
    t.string "status", default: "previewed", null: false
    t.string "summary"
    t.jsonb "operations", default: [], null: false
    t.jsonb "preview", default: {}, null: false
    t.jsonb "snapshots", default: [], null: false
    t.jsonb "results", default: {}, null: false
    t.jsonb "verification", default: {}, null: false
    t.integer "max_level", default: 1, null: false
    t.datetime "applied_at"
    t.datetime "verified_at"
    t.datetime "rolled_back_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_agent_changesets_on_status"
    t.index ["store_id", "token"], name: "index_agent_changesets_on_store_id_and_token", unique: true
    t.index ["store_id"], name: "index_agent_changesets_on_store_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.bigint "store_id"
    t.bigint "actor_user_id"
    t.string "actor_label"
    t.string "source", null: false
    t.boolean "acting_as_platform", default: false, null: false
    t.string "action", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "ip"
    t.datetime "created_at", null: false
    t.index ["action", "created_at"], name: "index_audit_events_on_action_and_created_at"
    t.index ["actor_user_id"], name: "index_audit_events_on_actor_user_id"
    t.index ["store_id", "created_at"], name: "index_audit_events_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_audit_events_on_store_id"
    t.check_constraint "source::text = ANY (ARRAY['ui'::character varying, 'api'::character varying, 'mcp'::character varying, 'job'::character varying, 'system'::character varying]::text[])", name: "audit_event_source"
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
    t.index ["store_id", "token"], name: "index_carts_on_store_id_and_token", unique: true
    t.index ["store_id"], name: "index_carts_on_store_id"
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

  create_table "confirmation_attempts", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "order_confirmation_id", null: false
    t.bigint "user_id"
    t.string "actor_label", null: false
    t.string "outcome", null: false
    t.text "notes"
    t.datetime "callback_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_confirmation_id"], name: "index_confirmation_attempts_on_order_confirmation_id"
    t.index ["store_id"], name: "index_confirmation_attempts_on_store_id"
    t.index ["user_id"], name: "index_confirmation_attempts_on_user_id"
    t.check_constraint "outcome::text = ANY (ARRAY['no_answer'::character varying, 'callback'::character varying, 'confirmed'::character varying, 'cancelled'::character varying]::text[])", name: "confirmation_attempt_outcome"
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

  create_table "invoices", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "number", null: false
    t.string "status", default: "draft", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "billing_interval", null: false
    t.date "period_starts_on", null: false
    t.date "period_ends_on", null: false
    t.date "due_on"
    t.datetime "issued_at"
    t.datetime "paid_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["status", "due_on"], name: "index_invoices_on_status_and_due_on"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["store_id"], name: "index_invoices_on_store_id"
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

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "token_digest", null: false
    t.string "refresh_digest", null: false
    t.string "client_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "refresh_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["refresh_digest"], name: "index_oauth_access_tokens_on_refresh_digest", unique: true
    t.index ["store_id"], name: "index_oauth_access_tokens_on_store_id"
    t.index ["token_digest"], name: "index_oauth_access_tokens_on_token_digest", unique: true
  end

  create_table "oauth_clients", force: :cascade do |t|
    t.string "client_id", null: false
    t.string "client_name"
    t.string "redirect_uris", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_oauth_clients_on_client_id", unique: true
  end

  create_table "order_confirmations", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "order_id", null: false
    t.bigint "assigned_user_id"
    t.datetime "claimed_at"
    t.string "disposition", default: "pending", null: false
    t.datetime "callback_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_user_id"], name: "index_order_confirmations_on_assigned_user_id"
    t.index ["order_id"], name: "index_order_confirmations_on_order_id", unique: true
    t.index ["store_id", "disposition", "callback_at"], name: "index_confirmation_queue"
    t.index ["store_id"], name: "index_order_confirmations_on_store_id"
    t.check_constraint "disposition::text = ANY (ARRAY['pending'::character varying, 'no_answer'::character varying, 'callback'::character varying, 'confirmed'::character varying, 'cancelled'::character varying]::text[])", name: "confirmation_disposition"
  end

  create_table "order_events", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_events_on_order_id"
    t.index ["user_id"], name: "index_order_events_on_user_id"
  end

  create_table "order_imports", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "order_id", null: false
    t.string "source", limit: 64, null: false
    t.string "external_id", limit: 255, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_imports_on_order_id"
    t.index ["store_id", "source", "external_id"], name: "index_order_imports_on_tenant_source_external_id", unique: true
    t.index ["store_id"], name: "index_order_imports_on_store_id"
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
    t.integer "discount_cents", default: 0, null: false
    t.string "discount_code"
    t.datetime "archived_at"
    t.string "tags"
    t.index ["archived_at"], name: "index_orders_on_archived_at"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["customer_phone"], name: "index_orders_on_customer_phone"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["store_id", "number"], name: "index_orders_on_store_id_and_number", unique: true
    t.index ["store_id", "sendit_code"], name: "index_orders_on_store_id_and_sendit_code", unique: true, where: "(sendit_code IS NOT NULL)"
    t.index ["store_id"], name: "index_orders_on_store_id"
  end

  create_table "page_section_translations", force: :cascade do |t|
    t.bigint "page_section_id", null: false
    t.string "locale", null: false
    t.string "heading"
    t.string "subheading"
    t.text "body"
    t.string "button_label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_section_id", "locale"], name: "index_page_section_translations_on_page_section_and_locale", unique: true
    t.index ["page_section_id"], name: "index_page_section_translations_on_page_section_id"
  end

  create_table "page_sections", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.boolean "visible", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id", "position"], name: "index_page_sections_on_page_id_and_position"
    t.index ["page_id"], name: "index_page_sections_on_page_id"
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
    t.string "template", default: "content", null: false
    t.index ["store_id", "slug"], name: "index_pages_on_store_id_and_slug", unique: true
    t.index ["store_id", "template"], name: "index_pages_on_store_id_and_template"
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
    t.string "color_hex"
    t.jsonb "image_order", default: [], null: false
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
    t.integer "shipping_cents", default: 0, null: false
    t.integer "free_shipping_threshold_cents"
    t.boolean "sendit_allow_open", default: true, null: false
    t.boolean "sendit_allow_try", default: true, null: false
    t.integer "low_stock_threshold", default: 5, null: false
    t.string "meta_pixel_id"
    t.string "tiktok_pixel_id"
    t.text "sendit_public_key"
    t.text "sendit_secret_key"
    t.text "sendit_webhook_secret"
    t.text "discord_orders_webhook_url"
    t.string "billing_interval", default: "monthly", null: false
    t.string "billing_status", default: "active", null: false
    t.integer "billing_amount_cents", default: 0, null: false
    t.date "billing_period_ends_on"
    t.string "legal_entity_name"
    t.string "cndp_authorization"
    t.string "privacy_rights_contact"
    t.string "api_token_digest"
    t.string "api_token_last_four"
    t.jsonb "agent_profile", default: {}, null: false
    t.index ["api_token_digest"], name: "index_stores_on_api_token_digest", unique: true
    t.index ["billing_interval"], name: "index_stores_on_billing_interval"
    t.index ["billing_status"], name: "index_stores_on_billing_status"
    t.index ["slug"], name: "index_stores_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name"
    t.boolean "admin", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "store_id"
    t.boolean "super_admin", default: false, null: false
    t.index ["email"], name: "index_users_on_email_super_admin", unique: true, where: "(super_admin = true)"
    t.index ["store_id", "email"], name: "index_users_on_store_id_and_email", unique: true
    t.index ["store_id"], name: "index_users_on_store_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "customers"
  add_foreign_key "admin_sessions", "stores", on_delete: :cascade
  add_foreign_key "admin_sessions", "users", on_delete: :cascade
  add_foreign_key "agent_changesets", "stores"
  add_foreign_key "audit_events", "stores", on_delete: :nullify
  add_foreign_key "audit_events", "users", column: "actor_user_id", on_delete: :nullify
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "product_variants"
  add_foreign_key "cart_items", "products"
  add_foreign_key "carts", "stores"
  add_foreign_key "collection_products", "collections"
  add_foreign_key "collection_products", "products"
  add_foreign_key "collection_translations", "collections"
  add_foreign_key "collections", "stores"
  add_foreign_key "confirmation_attempts", "order_confirmations", on_delete: :cascade
  add_foreign_key "confirmation_attempts", "stores", on_delete: :cascade
  add_foreign_key "confirmation_attempts", "users", on_delete: :nullify
  add_foreign_key "customers", "stores"
  add_foreign_key "discounts", "stores"
  add_foreign_key "home_section_translations", "home_sections"
  add_foreign_key "home_sections", "stores"
  add_foreign_key "inventory_movements", "orders"
  add_foreign_key "inventory_movements", "product_variants"
  add_foreign_key "inventory_movements", "products"
  add_foreign_key "invoices", "stores"
  add_foreign_key "menu_item_translations", "menu_items"
  add_foreign_key "menu_items", "stores"
  add_foreign_key "oauth_access_tokens", "stores"
  add_foreign_key "order_confirmations", "orders", on_delete: :cascade
  add_foreign_key "order_confirmations", "stores", on_delete: :cascade
  add_foreign_key "order_confirmations", "users", column: "assigned_user_id", on_delete: :nullify
  add_foreign_key "order_events", "orders"
  add_foreign_key "order_events", "users"
  add_foreign_key "order_imports", "orders", on_delete: :cascade
  add_foreign_key "order_imports", "stores", on_delete: :cascade
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "stores"
  add_foreign_key "page_section_translations", "page_sections"
  add_foreign_key "page_sections", "pages"
  add_foreign_key "page_translations", "pages"
  add_foreign_key "pages", "stores"
  add_foreign_key "product_translations", "products"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "stores"
  add_foreign_key "store_translations", "stores"
  add_foreign_key "users", "stores"
end
