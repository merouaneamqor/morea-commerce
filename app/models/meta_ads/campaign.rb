# frozen_string_literal: true

module MetaAds
  class Campaign < ApplicationRecord
    include MetaAds::Cached

    has_many :ad_sets, class_name: "MetaAds::AdSet", dependent: :restrict_with_error
    has_many :ads, class_name: "MetaAds::Ad", dependent: :restrict_with_error
    has_many :daily_insights, class_name: "MetaAds::DailyInsight", dependent: :restrict_with_error

    # True when Meta still reports the campaign as delivering.
    def running?
      effective_status.to_s == "ACTIVE"
    end

    # Campaign CBO daily/lifetime budget when set; otherwise nil (budgets may live on ad sets).
    def campaign_budget?
      daily_budget.present? || lifetime_budget.present?
    end
  end
end
