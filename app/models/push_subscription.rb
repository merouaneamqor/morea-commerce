class PushSubscription < ApplicationRecord
  belongs_to :store
  belongs_to :user

  validates :endpoint, presence: true, length: { maximum: 2048 }, format: { with: %r{\Ahttps://}, message: "must be an https push endpoint" }
  validates :p256dh, :auth, presence: true
  validate :user_belongs_to_store

  private

  def user_belongs_to_store
    errors.add(:user, "must belong to this store") if user && user.store_id != store_id
  end
end
