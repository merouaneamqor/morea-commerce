class AddConfirmationRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :confirmation_role, :string, null: false, default: "supervisor"
    add_check_constraint :users, "confirmation_role IN ('agent', 'supervisor')", name: "users_confirmation_role_check"
    # Confirmation agents work the desk without store admin rights.
    add_check_constraint :users, "confirmation_role <> 'agent' OR admin = FALSE", name: "users_agent_not_admin"
  end
end
