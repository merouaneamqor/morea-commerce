# frozen_string_literal: true

module MetaAds
  # Meta-reported figures for one day in the ad account's timezone. `spend` and `currency` are the account's
  # own; `spend_display` is the same amount converted to the store's currency with the rate and rate date used.
  # These are Meta-attributed and are never reconciled with Morea orders. Ad rows and campaign rows are two
  # views of the same spend: never add one level to the other.
  class DailyInsight < ApplicationRecord
    LEVELS = %w[account campaign ad].freeze
    COUNTS = %i[impressions reach clicks].freeze
    AMOUNTS = %i[spend conversions conversion_value].freeze

    belongs_to :store
    belongs_to :ad_account, class_name: "MetaAds::AdAccount"
    belongs_to :campaign, class_name: "MetaAds::Campaign", optional: true
    belongs_to :ad_set, class_name: "MetaAds::AdSet", optional: true
    belongs_to :ad, class_name: "MetaAds::Ad", optional: true
    attr_readonly :store_id, :ad_account_id, :campaign_id, :ad_id, :level, :date

    scope :at_level, ->(level) { where(level: level) }

    validates :level, inclusion: { in: LEVELS }
    validates :date, :currency, :synced_at, presence: true
    validates(*COUNTS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
    validates(*AMOUNTS, numericality: { greater_than_or_equal_to: 0 })
    validates :campaign, presence: true, if: -> { level.in?(%w[campaign ad]) }
    validates :campaign, absence: true, if: -> { level == "account" }
    validates :ad, presence: true, if: -> { level == "ad" }
    validates :ad, absence: true, unless: -> { level == "ad" }
    validate :same_store_parents

    private

    def same_store_parents
      errors.add(:ad_account, "must belong to the same store") if ad_account && ad_account.store_id != store_id
      [ campaign, ad_set, ad ].compact.each do |parent|
        errors.add(parent.class.model_name.element.to_sym, "must belong to the same ad account") if parent.store_id != store_id || parent.ad_account_id != ad_account_id
      end
    end
  end
end
