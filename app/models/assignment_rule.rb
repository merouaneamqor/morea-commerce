# A rule of the Règles d'attribution page. Conditions are all optional: an empty rule covers every order. See Confirmations::AssignmentRunner for
# how rules are applied (first matching rule in position order; equal or percentage split among the agents who are on shift).
class AssignmentRule < ApplicationRecord
  # equal = round robin with the same share each (50/50 with two agents); percent = a share given to each agent (70/30); least_loaded = the agent
  # with the fewest waiting orders; best_performance = the agent with the best success rate; random = any eligible agent.
  DISTRIBUTIONS = %w[equal percent least_loaded best_performance random].freeze
  MIN_TIMEOUT = 5
  MAX_TIMEOUT = 1440

  belongs_to :store
  has_many :assignment_rule_agents, -> { order(:id) }, dependent: :destroy, inverse_of: :assignment_rule
  has_many :agents, through: :assignment_rule_agents, source: :user
  has_many :order_confirmations, dependent: :nullify

  accepts_nested_attributes_for :assignment_rule_agents, allow_destroy: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_sources
  before_create { self.position = (store.assignment_rules.maximum(:position) || 0) + 1 if position.to_i.zero? }

  validates :name, presence: true, length: { maximum: 120 }
  validates :distribution, inclusion: { in: DISTRIBUTIONS }
  validates :min_success_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :timeout_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_TIMEOUT, less_than_or_equal_to: MAX_TIMEOUT }
  validates :min_amount_cents, :max_amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :amount_range_is_ordered
  validate :has_agents
  validate :percentages_add_up
  validate :agents_belong_to_the_store

  def equal? = distribution == "equal"
  def percent? = distribution == "percent"
  def min_success? = min_success_percent.to_i.positive?
  def all_sources? = sources.blank?

  # Does an order fall under this rule? Amount range (inclusive) and sources ("manual", or the id of a connected store).
  def matches?(order, source_key:)
    return false if min_amount_cents && order.total_cents < min_amount_cents
    return false if max_amount_cents && order.total_cents > max_amount_cents

    all_sources? || sources.include?(source_key.to_s)
  end

  # { user_id => weight }: 1 each when equal, the percentage when by percentage.
  def weights
    assignment_rule_agents.reject(&:marked_for_destruction?).to_h { |row| [ row.user_id, percent? ? row.percent.to_i : 1 ] }
  end

  private

  def normalize_sources
    self.sources = Array(sources).map(&:to_s).compact_blank.uniq
  end

  def amount_range_is_ordered
    errors.add(:max_amount_cents, "must not be below the minimum amount") if min_amount_cents && max_amount_cents && max_amount_cents < min_amount_cents
  end

  def live_agent_rows = assignment_rule_agents.reject(&:marked_for_destruction?)

  def has_agents
    errors.add(:base, "Choose at least one agent") if live_agent_rows.empty?
  end

  def percentages_add_up
    return unless percent? && live_agent_rows.any?

    total = live_agent_rows.sum { |row| row.percent.to_i }
    errors.add(:base, "The percentages must add up to 100 % (now #{total} %)") unless total == 100
  end

  def agents_belong_to_the_store
    live_agent_rows.each do |row|
      user = row.user
      errors.add(:base, "#{user&.name.presence || "An agent"} is not a confirmation agent of this store") unless user && user.store_id == store_id && user.confirmation_role == "agent" && user.active?
    end
  end
end
