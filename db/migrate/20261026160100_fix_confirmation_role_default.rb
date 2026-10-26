class FixConfirmationRoleDefault < ActiveRecord::Migration[8.1]
  # A dev database ran the earlier migration with default "agent" before the
  # default was corrected, so staff created in that window may be agents.
  def up
    change_column_default :users, :confirmation_role, from: "agent", to: "supervisor"
    # Accounts that were already store admins keep their access as supervisors.
    execute "UPDATE users SET confirmation_role = 'supervisor' WHERE confirmation_role = 'agent' AND admin = TRUE"
    # Fresh databases already get this constraint from the role migration.
    unless check_constraint_exists?(:users, name: "users_agent_not_admin")
      add_check_constraint :users, "confirmation_role <> 'agent' OR admin = FALSE", name: "users_agent_not_admin"
    end
  end

  def down
    remove_check_constraint :users, name: "users_agent_not_admin" if check_constraint_exists?(:users, name: "users_agent_not_admin")
    change_column_default :users, :confirmation_role, from: "supervisor", to: "agent"
  end
end
