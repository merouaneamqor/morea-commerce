# frozen_string_literal: true

class CreateStorefrontVisitsAndFunnelEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :storefront_visits do |t|
      t.references :store, null: false, foreign_key: true
      t.string :token, null: false, limit: 64
      t.string :landing_path, limit: 500
      t.string :last_path, limit: 500
      t.string :referrer, limit: 500
      t.string :utm_source, limit: 100
      t.string :utm_medium, limit: 100
      t.string :utm_campaign, limit: 200
      t.string :utm_term, limit: 200
      t.string :utm_content, limit: 200
      t.string :fbclid, limit: 255
      t.string :gclid, limit: 255
      t.string :ttclid, limit: 255
      t.string :meta_campaign_id, limit: 25
      t.string :meta_adset_id, limit: 25
      t.string :meta_ad_id, limit: 25
      t.string :funnel_stage, null: false, default: "landed", limit: 32
      t.references :order, foreign_key: true
      t.datetime :landed_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :converted_at
      t.timestamps
    end

    add_index :storefront_visits, %i[store_id token], unique: true
    add_index :storefront_visits, %i[store_id landed_at]
    add_index :storefront_visits, %i[store_id funnel_stage landed_at]
    add_index :storefront_visits, %i[store_id utm_source landed_at], where: "utm_source IS NOT NULL", name: "index_storefront_visits_on_store_utm_source"

    add_check_constraint :storefront_visits,
      "funnel_stage IN ('landed', 'product_viewed', 'added_to_cart', 'checkout_started', 'ordered')",
      name: "storefront_visits_funnel_stage"
    add_check_constraint :storefront_visits,
      "meta_campaign_id IS NULL OR meta_campaign_id ~ '^[0-9]{5,25}$'",
      name: "storefront_visits_meta_campaign_id_numeric"
    add_check_constraint :storefront_visits,
      "meta_adset_id IS NULL OR meta_adset_id ~ '^[0-9]{5,25}$'",
      name: "storefront_visits_meta_adset_id_numeric"
    add_check_constraint :storefront_visits,
      "meta_ad_id IS NULL OR meta_ad_id ~ '^[0-9]{5,25}$'",
      name: "storefront_visits_meta_ad_id_numeric"
    add_check_constraint :storefront_visits,
      "(meta_adset_id IS NULL AND meta_ad_id IS NULL) OR meta_campaign_id IS NOT NULL",
      name: "storefront_visits_meta_ids_need_campaign"

    create_table :storefront_funnel_events do |t|
      t.references :store, null: false, foreign_key: true
      t.references :storefront_visit, null: false, foreign_key: true
      t.string :name, null: false, limit: 32
      t.string :path, limit: 500
      t.bigint :product_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :storefront_funnel_events, %i[store_id name created_at]
    add_index :storefront_funnel_events, %i[storefront_visit_id name]

    add_check_constraint :storefront_funnel_events,
      "name IN ('landed', 'product_viewed', 'added_to_cart', 'checkout_started', 'abandoned', 'ordered')",
      name: "storefront_funnel_events_name"
  end
end
