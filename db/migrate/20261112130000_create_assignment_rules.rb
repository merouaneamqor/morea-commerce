# Attribution rules: who gets the orders that come in. A rule has conditions (an amount range, the sources it covers), the agents it
# spreads the orders over (equally, or with a percentage each), and a delay after which an order the agent did not confirm moves to
# another agent who is active and online. Rules run in priority order (position); the first one that matches an order decides.
class CreateAssignmentRules < ActiveRecord::Migration[8.1]
  def change
    create_table :assignment_rules do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false, limit: 120
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :distribution, null: false, default: "equal"
      t.integer :min_amount_cents
      t.integer :max_amount_cents
      t.jsonb :sources, null: false, default: []
      t.integer :timeout_minutes, null: false, default: 30
      t.boolean :transfer_on_timeout, null: false, default: true
      t.timestamps
    end
    add_index :assignment_rules, %i[store_id position]
    add_check_constraint :assignment_rules, "distribution IN ('equal', 'percent')", name: "assignment_rules_distribution"
    add_check_constraint :assignment_rules, "timeout_minutes BETWEEN 5 AND 1440", name: "assignment_rules_timeout"
    add_check_constraint :assignment_rules, "min_amount_cents IS NULL OR min_amount_cents >= 0", name: "assignment_rules_min_amount"
    add_check_constraint :assignment_rules, "max_amount_cents IS NULL OR min_amount_cents IS NULL OR max_amount_cents >= min_amount_cents", name: "assignment_rules_amount_range"

    create_table :assignment_rule_agents do |t|
      t.references :assignment_rule, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :percent
      t.timestamps
    end
    add_index :assignment_rule_agents, %i[assignment_rule_id user_id], unique: true, name: "index_rule_agents_on_rule_and_user"
    add_check_constraint :assignment_rule_agents, "percent IS NULL OR percent BETWEEN 0 AND 100", name: "assignment_rule_agents_percent"

    add_reference :order_confirmations, :assignment_rule, foreign_key: { on_delete: :nullify }, index: true, null: true
  end
end
