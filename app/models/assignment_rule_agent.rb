class AssignmentRuleAgent < ApplicationRecord
  belongs_to :assignment_rule, inverse_of: :assignment_rule_agents
  belongs_to :user

  validates :user_id, uniqueness: { scope: :assignment_rule_id }
  validates :percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
end
