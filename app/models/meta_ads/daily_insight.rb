# frozen_string_literal: true

module MetaAds
  # Meta-reported figures for one day in the ad account's timezone and currency.
  # These are Meta-attributed and are never reconciled with Morea orders.
  class DailyInsight < ApplicationRecord
    LEVELS = %w[account campaign].freeze
    COUNTS = %i[impressions reach clicks].freeze
    AMOUNTS = %i[spend conversions conversion_value].freeze

    belongs_to :store
    belongs_to :ad_account, class_name: "MetaAds::AdAccount"
    belongs_to :campaign, class_name: "MetaAds::Campaign", optional: true
    attr_readonly :store_id, :ad_account_id, :campaign_id, :level, :date

    validates :level, inclusion: { in: LEVELS }
    validates :date, :currency, :synced_at, presence: true
    validates(*COUNTS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
    validates(*AMOUNTS, numericality: { greater_than_or_equal_to: 0 })
    validates :campaign, presence: true, if: -> { level == "campaign" }
    validates :campaign, absence: true, if: -> { level == "account" }
    validate :same_store_parents

    private

    def same_store_parents
      errors.add(:ad_account, "must belong to the same store") if ad_account && ad_account.store_id != store_id
      return unless campaign && (campaign.store_id != store_id || campaign.ad_account_id != ad_account_id)

      errors.add(:campaign, "must belong to the same ad account")
    end
  end
end
