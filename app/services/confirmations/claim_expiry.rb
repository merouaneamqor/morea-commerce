module Confirmations
  # A claim must not block an order forever. It is released automatically after 15 minutes with no
  # activity (claim, call opened, heartbeat of the open call panel, outcome) and when the agent clocks
  # out. Owners and managers can also release it by hand (Desk#force_release). Every release is written
  # to the order history.
  class ClaimExpiry
    IDLE_LIMIT = 15.minutes

    # Releases every idle claim of the store. Called before each desk action and by the cron job.
    def self.release_idle!(store)
      idle = OrderConfirmation.where(store: store).where.not(assigned_user_id: nil)
        .where("COALESCE(order_confirmations.last_activity_at, order_confirmations.claimed_at) < ?", IDLE_LIMIT.ago)
      idle.includes(:order, :assigned_user).find_each do |confirmation|
        release!(confirmation, "Claim released automatically after #{IDLE_LIMIT.in_minutes.to_i} minutes without activity")
      end
    end

    # The agent clocked out: whatever she still holds goes back to the queue.
    def self.release_for!(store:, user:)
      OrderConfirmation.where(store: store, assigned_user_id: user.id).includes(:order).find_each do |confirmation|
        release!(confirmation, "Claim released: the agent clocked out")
      end
    end

    def self.release!(confirmation, reason)
      confirmation.with_lock do
        next if confirmation.assigned_user_id.nil?

        confirmation.update!(assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil)
        confirmation.order.record_event!("comment", body: reason)
      end
    end
  end
end
