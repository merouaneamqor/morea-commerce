# Who created a team account, for the team page ("Créé par"). Accounts that existed before, or were created by the platform, have none.
class AddCreatedByToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
