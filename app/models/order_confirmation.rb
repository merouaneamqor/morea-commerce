class OrderConfirmation < ApplicationRecord
  DISPOSITIONS = %w[pending no_answer callback confirmed cancelled wrong_number blocked].freeze

  belongs_to :store
  belongs_to :order
  belongs_to :assigned_user, class_name: "User", optional: true
  # Who the order is for (durable, set by an owner, a supervisor or the automatic attribution); assigned_user is the short claim.
  belongs_to :attributed_user, class_name: "User", optional: true
  has_many :confirmation_attempts, dependent: :destroy

  validates :order_id, uniqueness: true
  validates :disposition, inclusion: { in: DISPOSITIONS }
  validates :callback_at, presence: true, if: -> { disposition == "callback" }
  validate :same_store_records

  def due?
    callback_at.nil? || callback_at <= Time.current
  end

  private

  def same_store_records
    errors.add(:order, "must belong to this store") if order && order.store_id != store_id
    if assigned_user && !assigned_user.can_work_desk_for?(store_id)
      errors.add(:assigned_user, "must administer this store")
    end
    errors.add(:attributed_user, "must work the desk of this store") if attributed_user && !attributed_user.can_work_desk_for?(store_id)
  end
end
