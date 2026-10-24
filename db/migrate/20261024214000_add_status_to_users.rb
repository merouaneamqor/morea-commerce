class AddStatusToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :status, :string, null: false, default: "active"
    add_column :users, :status_changed_at, :datetime
    add_check_constraint :users, "status IN ('active', 'suspended', 'archived')", name: "users_status_check"
    add_index :users, :status
  end
end
