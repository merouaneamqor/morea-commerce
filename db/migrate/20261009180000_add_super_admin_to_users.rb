# frozen_string_literal: true

class AddSuperAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :super_admin, :boolean, default: false, null: false
    change_column_null :users, :store_id, true

    add_index :users, :email, unique: true, where: "super_admin = TRUE", name: "index_users_on_email_super_admin"
  end
end
