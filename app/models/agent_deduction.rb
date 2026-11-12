# A penalty taken from an agent's commission when an order she confirmed ends up returned.
# The amount is the agent's "return penalty" (Team) at that moment, frozen here. It stays "pending"
# until the next payout, which subtracts it and marks it "applied".
class AgentDeduction < ApplicationRecord
  STATUSES = %w[pending applied].freeze

  belongs_to :store
  belongs_to :user
  belongs_to :order
  belongs_to :agent_payment, optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :order_id, uniqueness: true

  scope :pending, -> { where(status: "pending") }

  # Called when an order becomes returned. One deduction per order, none when the penalty is 0 or when
  # nobody confirmed the order (a manager-confirmed order has no agent to penalise).
  def self.record_for!(order)
    agent = ConfirmationAttempt.joins(:order_confirmation)
      .where(order_confirmations: { order_id: order.id }, outcome: "confirmed").order(:created_at).last&.user
    return unless agent&.confirmation_agent? && agent.return_penalty_cents.to_i.positive?
    return if exists?(order_id: order.id)

    create!(store: order.store, user: agent, order: order, amount_cents: agent.return_penalty_cents)
  end
end
