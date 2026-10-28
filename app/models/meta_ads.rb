# frozen_string_literal: true

# Read-only Meta Ads cache and credentials. Everything under this namespace belongs to one store.
module MetaAds
  def self.table_name_prefix
    "meta_ads_"
  end
end
