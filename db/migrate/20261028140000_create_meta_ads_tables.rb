# frozen_string_literal: true

# Read-only Meta Ads cache. Every row carries store_id; children reference their
# ad account through a composite key so a row cannot point at another store's account.
class CreateMetaAdsTables < ActiveRecord::Migration[8.0]
  def change
    create_table :meta_ads_connections do |t|
      t.references :store, null: false, foreign_key: true, index: { unique: true }
      t.string :meta_user_id
      t.text :access_token_ciphertext
      t.datetime :token_expires_at
      t.string :status, null: false, default: "active"
      t.string :granted_scopes, array: true, null: false, default: []
      t.datetime :last_verified_at
      t.string :last_error_code
      t.string :oauth_state_digest
      t.datetime :oauth_state_expires_at
      t.timestamps
      t.index :oauth_state_digest, unique: true
      t.check_constraint "status IN ('active', 'needs_reauthorization', 'disconnected')", name: "meta_ads_connection_status"
      t.check_constraint "status <> 'active' OR access_token_ciphertext IS NOT NULL", name: "meta_ads_connection_active_token"
    end

    create_table :meta_ads_ad_accounts do |t|
      t.references :store, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: { to_table: :meta_ads_connections }
      t.references :advertising_account, foreign_key: true
      t.string :meta_ad_account_id, null: false
      t.string :name
      t.string :currency
      t.string :timezone_name
      t.boolean :selected, null: false, default: false
      t.string :sync_status, null: false, default: "pending"
      t.datetime :last_attempt_at
      t.datetime :last_synced_at
      t.datetime :structure_synced_at
      t.datetime :insights_backfilled_at
      t.datetime :next_sync_at
      t.integer :retry_count, null: false, default: 0
      t.string :last_error_code
      t.string :last_error_message
      t.timestamps
      t.index %i[store_id meta_ad_account_id], unique: true
      t.index :meta_ad_account_id, unique: true, where: "selected", name: "index_meta_ads_ad_accounts_selected_unique"
      t.index %i[id store_id], unique: true, name: "index_meta_ads_ad_accounts_on_id_and_store_id"
      t.check_constraint "meta_ad_account_id ~ '^act_[0-9]+$'", name: "meta_ads_ad_account_id_format"
      t.check_constraint "sync_status IN ('pending', 'ok', 'running', 'rate_limited', 'needs_reauthorization', 'failed')", name: "meta_ads_ad_account_sync_status"
      t.check_constraint "retry_count >= 0", name: "meta_ads_ad_account_retry_count"
    end

    create_table :meta_ads_campaigns do |t|
      t.references :store, null: false, foreign_key: true
      t.references :ad_account, null: false, index: false
      t.string :meta_id, null: false
      t.string :name
      t.string :status
      t.string :effective_status
      t.string :objective
      t.datetime :meta_updated_at
      t.datetime :last_seen_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
      t.index %i[ad_account_id meta_id], unique: true
      t.index %i[id store_id], unique: true, name: "index_meta_ads_campaigns_on_id_and_store_id"
    end

    create_table :meta_ads_ad_sets do |t|
      t.references :store, null: false, foreign_key: true
      t.references :ad_account, null: false, index: false
      t.references :campaign, foreign_key: { to_table: :meta_ads_campaigns }
      t.string :meta_id, null: false
      t.string :name
      t.string :status
      t.string :effective_status
      t.datetime :meta_updated_at
      t.datetime :last_seen_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
      t.index %i[ad_account_id meta_id], unique: true
      t.index %i[id store_id], unique: true, name: "index_meta_ads_ad_sets_on_id_and_store_id"
    end

    create_table :meta_ads_ads do |t|
      t.references :store, null: false, foreign_key: true
      t.references :ad_account, null: false, index: false
      t.references :ad_set, foreign_key: { to_table: :meta_ads_ad_sets }
      t.references :campaign, foreign_key: { to_table: :meta_ads_campaigns }
      t.string :meta_id, null: false
      t.string :name
      t.string :status
      t.string :effective_status
      t.datetime :meta_updated_at
      t.datetime :last_seen_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
      t.index %i[ad_account_id meta_id], unique: true
    end

    create_table :meta_ads_daily_insights do |t|
      t.references :store, null: false, foreign_key: true
      t.references :ad_account, null: false, index: false
      t.references :campaign, foreign_key: { to_table: :meta_ads_campaigns }
      t.string :level, null: false
      t.date :date, null: false
      t.bigint :impressions, null: false, default: 0
      t.bigint :reach, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.decimal :spend, precision: 18, scale: 4, null: false, default: 0
      t.decimal :ctr, precision: 12, scale: 6
      t.decimal :cpc, precision: 18, scale: 6
      t.decimal :cpm, precision: 18, scale: 6
      t.decimal :conversions, precision: 18, scale: 4, null: false, default: 0
      t.decimal :conversion_value, precision: 18, scale: 4, null: false, default: 0
      t.decimal :roas, precision: 12, scale: 4
      t.string :currency, null: false
      t.jsonb :raw_actions, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
      t.index %i[ad_account_id campaign_id date], unique: true, where: "level = 'campaign'", name: "index_meta_ads_insights_campaign_day"
      t.index %i[ad_account_id date], unique: true, where: "level = 'account'", name: "index_meta_ads_insights_account_day"
      t.index %i[store_id date]
      t.check_constraint "level IN ('account', 'campaign')", name: "meta_ads_insight_level"
      t.check_constraint "(level = 'campaign') = (campaign_id IS NOT NULL)", name: "meta_ads_insight_campaign_presence"
      t.check_constraint "impressions >= 0 AND reach >= 0 AND clicks >= 0 AND spend >= 0 AND conversions >= 0 AND conversion_value >= 0", name: "meta_ads_insight_non_negative"
    end

    %i[campaigns ad_sets ads daily_insights].each do |table|
      add_foreign_key "meta_ads_#{table}", :meta_ads_ad_accounts, column: %i[ad_account_id store_id], primary_key: %i[id store_id]
    end
  end
end
