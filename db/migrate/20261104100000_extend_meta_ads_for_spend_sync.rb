# frozen_string_literal: true

# Spend sync at campaign and ad level, the exchange rate used for each row, ad-to-product links
# and the record of Meta data deletion requests.
class ExtendMetaAdsForSpendSync < ActiveRecord::Migration[8.0]
  def change
    add_column :meta_ads_ad_accounts, :account_status, :integer

    change_table :meta_ads_daily_insights, bulk: true do |t|
      t.references :ad_set, foreign_key: { to_table: :meta_ads_ad_sets }
      t.references :ad, foreign_key: { to_table: :meta_ads_ads }
      t.string :meta_campaign_id
      t.string :meta_adset_id
      t.string :meta_ad_id
      t.string :campaign_name
      t.string :adset_name
      t.string :ad_name
      t.decimal :spend_display, precision: 18, scale: 4
      t.string :display_currency
      t.decimal :fx_rate, precision: 18, scale: 8
      t.date :fx_date
    end

    remove_check_constraint :meta_ads_daily_insights, name: "meta_ads_insight_level"
    remove_check_constraint :meta_ads_daily_insights, name: "meta_ads_insight_campaign_presence"
    add_check_constraint :meta_ads_daily_insights, "level IN ('account', 'campaign', 'ad')", name: "meta_ads_insight_level"
    add_check_constraint :meta_ads_daily_insights, "(level IN ('campaign', 'ad')) = (campaign_id IS NOT NULL)", name: "meta_ads_insight_campaign_presence"
    add_check_constraint :meta_ads_daily_insights, "(level = 'ad') = (ad_id IS NOT NULL)", name: "meta_ads_insight_ad_presence"
    add_check_constraint :meta_ads_daily_insights, "(spend_display IS NULL) = (fx_rate IS NULL)", name: "meta_ads_insight_display_has_rate"
    add_index :meta_ads_daily_insights, %i[ad_account_id ad_id date], unique: true, where: "level = 'ad'", name: "index_meta_ads_insights_ad_day"

    create_table :exchange_rates do |t|
      t.string :base_currency, null: false
      t.string :quote_currency, null: false
      t.decimal :rate, precision: 18, scale: 8, null: false
      t.date :rate_date, null: false
      t.string :source, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index %i[base_currency quote_currency rate_date], unique: true, name: "index_exchange_rates_on_pair_and_date"
      t.check_constraint "rate > 0", name: "exchange_rates_positive"
      t.check_constraint "base_currency ~ '^[A-Z]{3}$' AND quote_currency ~ '^[A-Z]{3}$'", name: "exchange_rates_currency_format"
    end

    create_table :meta_ads_product_links do |t|
      t.references :store, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :object_type, null: false
      t.string :meta_id, null: false
      t.string :source, null: false, default: "manual"
      t.timestamps
      t.index %i[store_id object_type meta_id], unique: true, name: "index_meta_ads_product_links_on_object"
      t.check_constraint "object_type IN ('ad', 'ad_set', 'campaign')", name: "meta_ads_product_link_type"
      t.check_constraint "source IN ('manual', 'auto')", name: "meta_ads_product_link_source"
    end

    create_table :meta_ads_deletion_requests do |t|
      t.string :confirmation_code, null: false
      t.string :meta_user_digest, null: false
      t.string :status, null: false, default: "completed"
      t.integer :connections_removed, null: false, default: 0
      t.timestamps
      t.index :confirmation_code, unique: true
      t.check_constraint "status IN ('pending', 'completed')", name: "meta_ads_deletion_status"
    end
  end
end
