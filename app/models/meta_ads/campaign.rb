# frozen_string_literal: true

module MetaAds
  class Campaign < ApplicationRecord
    include MetaAds::Cached

    has_many :ad_sets, class_name: "MetaAds::AdSet", dependent: :restrict_with_error
    has_many :ads, class_name: "MetaAds::Ad", dependent: :restrict_with_error
    has_many :daily_insights, class_name: "MetaAds::DailyInsight", dependent: :restrict_with_error
  end
end
