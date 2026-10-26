class AddHandledSecondsToConfirmationAttempts < ActiveRecord::Migration[8.1]
  def change
    # Seconds the agent held the order before recording this outcome; null for older attempts.
    add_column :confirmation_attempts, :handled_seconds, :integer
    add_check_constraint :confirmation_attempts, "handled_seconds IS NULL OR handled_seconds >= 0", name: "confirmation_attempt_handled_nonnegative"
  end
end
