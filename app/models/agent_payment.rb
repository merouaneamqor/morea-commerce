class AgentPayment < ApplicationRecord
  belongs_to :store
  belongs_to :user
  belongs_to :paid_by, class_name: "User", optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :paid_at, presence: true
  validate :user_belongs_to_store

  private

  def user_belongs_to_store
    errors.add(:user, "must belong to this store") if user && user.store_id != store_id
  end
end
