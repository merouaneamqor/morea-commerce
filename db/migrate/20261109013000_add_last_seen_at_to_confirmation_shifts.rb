class AddLastSeenAtToConfirmationShifts < ActiveRecord::Migration[8.1]
  def change
    add_column :confirmation_shifts, :last_seen_at, :datetime
  end
end
