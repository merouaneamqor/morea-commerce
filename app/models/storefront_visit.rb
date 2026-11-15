# frozen_string_literal: true

# One anonymous storefront session for first-party attribution and funnel reach.
# Written only when measurement is allowed (same gate as pixels).
class StorefrontVisit < ApplicationRecord
  STAGES = %w[landed product_viewed added_to_cart checkout_started ordered].freeze
  STAGE_RANK = STAGES.each_with_index.to_h.freeze

  belongs_to :store
  belongs_to :order, optional: true
  has_many :storefront_funnel_events, dependent: :delete_all

  validates :token, presence: true, uniqueness: { scope: :store_id }
  validates :funnel_stage, inclusion: { in: STAGES }
  validates :landed_at, :last_seen_at, presence: true

  scope :in_range, ->(range) { where(landed_at: range) }
  scope :attributed, -> { where.not(utm_source: [ nil, "" ]).or(where.not(fbclid: [ nil, "" ])).or(where.not(gclid: [ nil, "" ])).or(where.not(ttclid: [ nil, "" ])) }

  def advance_stage!(stage)
    stage = stage.to_s
    return unless STAGES.include?(stage)
    return if STAGE_RANK.fetch(stage) <= STAGE_RANK.fetch(funnel_stage)

    self.funnel_stage = stage
  end

  def source_label
    return "meta" if meta_campaign_id.present? || utm_source.to_s.downcase.in?(%w[facebook ig instagram meta])
    return "tiktok" if ttclid.present? || utm_source.to_s.downcase.in?(%w[tiktok tt])
    return "google" if gclid.present? || utm_source.to_s.downcase.in?(%w[google adwords])
    return utm_source if utm_source.present?
    return "referral" if referrer.present?

    "direct"
  end
end
