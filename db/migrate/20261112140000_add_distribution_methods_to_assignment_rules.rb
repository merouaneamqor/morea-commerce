# More ways to pick the agent (lowest load, best performance, random) and a performance criterion on the agents a rule may use.
class AddDistributionMethodsToAssignmentRules < ActiveRecord::Migration[8.1]
  def change
    add_column :assignment_rules, :min_success_percent, :integer
    remove_check_constraint :assignment_rules, "distribution IN ('equal', 'percent')", name: "assignment_rules_distribution"
    add_check_constraint :assignment_rules, "distribution IN ('equal', 'percent', 'least_loaded', 'best_performance', 'random')", name: "assignment_rules_distribution"
    add_check_constraint :assignment_rules, "min_success_percent IS NULL OR min_success_percent BETWEEN 0 AND 100", name: "assignment_rules_min_success"
  end
end
