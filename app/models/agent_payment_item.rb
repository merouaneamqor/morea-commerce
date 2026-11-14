# One order settled by a payout, with what it paid (the agent's rate at that time). An order appears in at most one payout.
class AgentPaymentItem < ApplicationRecord
  belongs_to :store
  belongs_to :agent_payment
  belongs_to :user
  belongs_to :order

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :order_id, uniqueness: true
end
