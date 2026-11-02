class ReduceAdminThemesToSeallo < ActiveRecord::Migration[8.1]
  OLD = "('blue', 'dark', 'light', 'current')"
  NEW = "('seallo', 'seallo_dark')"

  # Dark workspaces become dark seallo; blue, light and current become seallo.
  def up
    remove_constraints
    %i[stores registrations].each do |table|
      execute "UPDATE #{table} SET admin_theme = CASE admin_theme WHEN 'dark' THEN 'seallo_dark' ELSE 'seallo' END"
      change_column_default table, :admin_theme, from: table == :stores ? "current" : "blue", to: "seallo"
    end
    add_constraints(NEW)
  end

  def down
    remove_constraints
    execute "UPDATE stores SET admin_theme = CASE admin_theme WHEN 'seallo_dark' THEN 'dark' ELSE 'current' END"
    execute "UPDATE registrations SET admin_theme = CASE admin_theme WHEN 'seallo_dark' THEN 'dark' ELSE 'blue' END"
    change_column_default :stores, :admin_theme, from: "seallo", to: "current"
    change_column_default :registrations, :admin_theme, from: "seallo", to: "blue"
    add_constraints(OLD)
  end

  private

  def remove_constraints
    remove_check_constraint :stores, name: "stores_admin_theme"
    remove_check_constraint :registrations, name: "registrations_admin_theme"
  end

  def add_constraints(values)
    add_check_constraint :stores, "admin_theme IN #{values}", name: "stores_admin_theme"
    add_check_constraint :registrations, "admin_theme IN #{values}", name: "registrations_admin_theme"
  end
end
