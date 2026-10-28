# frozen_string_literal: true

module MetaAds
  class Ad < ApplicationRecord
    include MetaAds::Cached

    belongs_to :ad_set, class_name: "MetaAds::AdSet", optional: true
    belongs_to :campaign, class_name: "MetaAds::Campaign", optional: true
    validate { same_store_parent(:ad_set) }
    validate { same_store_parent(:campaign) }
  end
end
