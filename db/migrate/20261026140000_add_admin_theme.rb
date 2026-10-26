class AddAdminTheme < ActiveRecord::Migration[8.0]
  THEMES = "('blue', 'dark', 'light', 'current')"

  def change
    # Existing workspaces keep today's look; new sign-ups pick a theme (blue by default).
    add_column :stores, :admin_theme, :string, null: false, default: "current"
    add_column :registrations, :admin_theme, :string, null: false, default: "blue"
    add_check_constraint :stores, "admin_theme IN #{THEMES}", name: "stores_admin_theme"
    add_check_constraint :registrations, "admin_theme IN #{THEMES}", name: "registrations_admin_theme"
  end
end
