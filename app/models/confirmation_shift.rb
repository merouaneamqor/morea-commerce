class ConfirmationShift < ApplicationRecord
  belongs_to :store
  belongs_to :user, optional: true

  # Hours history outlives the account: the actor label is kept when staff are deleted.
  before_validation :capture_actor, on: :create
  validates :user, presence: true, on: :create
  validates :actor_label, presence: true
  validates :started_at, presence: true
  validates :ended_at, comparison: { greater_than: :started_at }, allow_nil: true
  validate :same_store_records

  scope :open, -> { where(ended_at: nil) }
  scope :overlapping, ->(range) { where("confirmation_shifts.started_at < ?", range.end).where("confirmation_shifts.ended_at IS NULL OR confirmation_shifts.ended_at > ?", range.begin) }

  # Seconds this shift worked inside the range; open shifts run until `now`.
  def seconds_within(range, now: Time.current)
    from = [ started_at, range.begin ].max
    to = [ ended_at || now, range.end ].min
    [ to - from, 0 ].max
  end

  private

  def capture_actor
    self.actor_label = user.name.presence || user.email if user
  end

  def same_store_records
    return unless user

    errors.add(:user, "must work this store's desk") unless user.can_work_desk_for?(store_id)
  end
end
