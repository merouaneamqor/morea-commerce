class AddSessionVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :session_version, :integer, default: 0, null: false
    add_check_constraint :users, "session_version >= 0", name: "users_session_version_nonnegative"
  end
end
