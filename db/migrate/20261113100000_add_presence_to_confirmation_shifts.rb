# An agent on shift proves they are still there with a heartbeat from the page; a shift with no sign of life is closed at the last one.
class AddPresenceToConfirmationShifts < ActiveRecord::Migration[8.1]
  def change
    # last_seen_at was already added by 20261109013000 on databases that ran it (production did): skip what is there, so this migration runs on both.
    add_column :confirmation_shifts, :last_seen_at, :datetime unless column_exists?(:confirmation_shifts, :last_seen_at)
    add_column :confirmation_shifts, :end_reason, :string unless column_exists?(:confirmation_shifts, :end_reason)
    unless check_constraint_exists?(:confirmation_shifts, name: "confirmation_shifts_end_reason")
      add_check_constraint :confirmation_shifts, "end_reason IS NULL OR end_reason IN ('manual', 'inactive')", name: "confirmation_shifts_end_reason"
    end

    # Shifts open at deploy time get a fresh sign of life, so they are not closed the minute the job first runs.
    reversible do |direction|
      direction.up { execute "UPDATE confirmation_shifts SET last_seen_at = NOW() WHERE ended_at IS NULL" }
    end
  end
end
