# Self-service plan chosen on the seallo signup. NULL means a workspace that predates plans.
class AddSubscriptionPlanToStores < ActiveRecord::Migration[8.1]
  PLANS = "('free', 'starter', 'intermediate', 'professional', 'business')"

  def change
    add_column :stores, :plan, :string
    add_column :stores, :trial_ends_at, :datetime
    add_check_constraint :stores, "plan IS NULL OR plan IN #{PLANS}", name: "stores_plan_known"
  end
end
