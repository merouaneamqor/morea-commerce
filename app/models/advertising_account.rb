class AdvertisingAccount < ApplicationRecord
  PROVIDERS = %w[Meta Google TikTok Other].freeze
  belongs_to :store
  has_many :advertising_campaigns, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 100 }
  validates :provider, inclusion: { in: PROVIDERS }
end
