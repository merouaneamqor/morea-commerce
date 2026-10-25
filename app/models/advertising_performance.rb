class AdvertisingPerformance < ApplicationRecord
  METRICS = %i[spend_cents delivered_revenue_cents fulfillment_cost_cents confirmed_orders delivered_orders clicks impressions].freeze
  belongs_to :advertising_campaign
  validates :date, presence: true, uniqueness: { scope: :advertising_campaign_id }
  validates(*METRICS, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 9_000_000_000_000 })
end
