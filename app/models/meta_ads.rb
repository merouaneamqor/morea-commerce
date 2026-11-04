# frozen_string_literal: true

# Meta Ads cache, credentials and ad-to-product links. Everything under this namespace belongs to one store.
module MetaAds
  # Child-first, so foreign keys never block the deletion.
  PURGE_ORDER = %w[meta_ads_product_links meta_ads_daily_insights meta_ads_ads meta_ads_ad_sets meta_ads_campaigns meta_ads_ad_accounts meta_ads_connections].freeze

  def self.table_name_prefix
    "meta_ads_"
  end

  # Removes every Meta row of a store (used when a workspace is reset or deleted).
  def self.purge_store!(store_id)
    connection = ActiveRecord::Base.connection
    PURGE_ORDER.each do |table|
      next unless connection.table_exists?(table)

      connection.delete(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE store_id = ?", store_id ]))
    end
  end
end
