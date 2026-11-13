class AdvertisingCampaign < ApplicationRecord
  belongs_to :advertising_account
  has_many :advertising_performances, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 150 }
end
