# frozen_string_literal: true

module MetaAds
  class AdSet < ApplicationRecord
    include MetaAds::Cached

    belongs_to :campaign, class_name: "MetaAds::Campaign", optional: true
    has_many :ads, class_name: "MetaAds::Ad", dependent: :restrict_with_error
    validate { same_store_parent(:campaign) }
  end
end
