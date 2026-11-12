# Applies the attribution rules of every store that has an active one: new orders go to the agents the rules choose, and orders an agent did not
# confirm in time move to another agent who is online. Runs every minute.
class AssignmentRulesJob < ApplicationJob
  queue_as :default

  def perform
    Confirmations::AssignmentRunner.run_all!
  end
end
