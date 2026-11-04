# frozen_string_literal: true

module MetaAds
  class AdAccount < ApplicationRecord
    SYNC_STATUSES = %w[pending ok running rate_limited needs_reauthorization failed].freeze

    belongs_to :store
    belongs_to :connection, class_name: "MetaAds::Connection"
    belongs_to :advertising_account, optional: true
    has_many :campaigns, class_name: "MetaAds::Campaign", dependent: :restrict_with_error
    has_many :ad_sets, class_name: "MetaAds::AdSet", dependent: :restrict_with_error
    has_many :ads, class_name: "MetaAds::Ad", dependent: :restrict_with_error
    has_many :daily_insights, class_name: "MetaAds::DailyInsight", dependent: :restrict_with_error
    attr_readonly :store_id, :meta_ad_account_id

    # Meta account_status: 1 ACTIVE, 2 DISABLED, 3 UNSETTLED, 7 PENDING_RISK_REVIEW, 8 PENDING_SETTLEMENT,
    # 9 IN_GRACE_PERIOD, 100 PENDING_CLOSURE, 101 CLOSED. Only accounts that are running normally can be linked.
    SELECTABLE_STATUSES = [ 1, 9 ].freeze

    scope :selected, -> { where(selected: true) }

    def selectable?
      SELECTABLE_STATUSES.include?(account_status)
    end

    def status_key
      { 1 => "active", 2 => "disabled", 3 => "unsettled", 7 => "pending_risk_review", 8 => "pending_settlement",
        9 => "grace_period", 100 => "pending_closure", 101 => "closed" }.fetch(account_status, "unknown")
    end

    validates :meta_ad_account_id, format: { with: /\Aact_[0-9]+\z/ }, uniqueness: { scope: :store_id }
    validates :sync_status, inclusion: { in: SYNC_STATUSES }
    validates :currency, :timezone_name, presence: true, if: :selected?
    validate :connection_in_same_store
    validate :advertising_account_in_same_store

    private

    def connection_in_same_store
      errors.add(:connection, "must belong to the same store") if connection && connection.store_id != store_id
    end

    def advertising_account_in_same_store
      errors.add(:advertising_account, "must belong to the same store") if advertising_account && advertising_account.store_id != store_id
    end
  end
end
