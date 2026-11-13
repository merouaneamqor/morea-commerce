# Closes the shifts of agents who left the page or the phone: no heartbeat for a few minutes means the agent is not there any more,
# so the shift ends at the last time they were seen and the orders they held go back to the queue. Runs every minute.
class CloseStaleShiftsJob < ApplicationJob
  queue_as :default

  def perform
    Confirmations::Shifts.close_stale!
  end
end
