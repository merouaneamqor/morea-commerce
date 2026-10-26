class ConfirmationAttempt < ApplicationRecord
  OUTCOMES = %w[no_answer callback confirmed cancelled].freeze

  belongs_to :store
  belongs_to :order_confirmation
  belongs_to :user, optional: true

  before_validation :capture_actor, on: :create
  validates :user, presence: true, on: :create
  validates :actor_label, presence: true

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :notes, length: { maximum: 2000 }
  validates :handled_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :callback_at, presence: true, if: -> { outcome == "callback" }
  validate :same_store_records

  private

  def capture_actor
    self.actor_label = user.name.presence || user.email if user
  end

  def same_store_records
    if order_confirmation && order_confirmation.store_id != store_id
      errors.add(:order_confirmation, "must belong to this store")
    end
    if user && !user.can_work_desk_for?(store_id)
      errors.add(:user, "must administer this store")
    end
  end
end
