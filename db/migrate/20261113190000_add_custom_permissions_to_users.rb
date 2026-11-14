# Per-user application permissions: the list of areas (Team::Roles::AREAS keys) the owner left open for this person. NULL means "what their role gives". A custom list can only
# narrow the role (the model drops anything the role does not give).
class AddCustomPermissionsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :custom_permissions, :jsonb
  end
end
