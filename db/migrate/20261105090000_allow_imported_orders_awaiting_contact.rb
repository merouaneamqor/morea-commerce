# frozen_string_literal: true

class AllowImportedOrdersAwaitingContact < ActiveRecord::Migration[8.0]
  def up
    add_column :orders, :import_contact_issues, :jsonb, default: [], null: false
    %i[customer_id customer_name customer_phone customer_city customer_address].each do |column|
      change_column_null :orders, column, true
    end
    add_check_constraint :orders,
      "jsonb_typeof(import_contact_issues) = 'array' AND import_contact_issues <@ '[\"name\",\"phone\",\"city\",\"address\"]'::jsonb",
      name: "orders_import_contact_issues_valid"
    add_check_constraint :orders,
      "import_contact_issues = '[]'::jsonb OR status IN ('new', 'cancelled')",
      name: "orders_pending_contact_unshipped"
    add_check_constraint :orders,
      "import_contact_issues <> '[]'::jsonb OR (customer_id IS NOT NULL AND customer_name IS NOT NULL AND customer_phone IS NOT NULL AND customer_city IS NOT NULL AND customer_address IS NOT NULL)",
      name: "orders_complete_contact_required"
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM orders WHERE customer_id IS NULL OR customer_name IS NULL OR customer_phone IS NULL OR customer_city IS NULL OR customer_address IS NULL)")
      raise ActiveRecord::IrreversibleMigration, "Complete or resolve imported contact reviews before restoring required contact columns."
    end
    remove_check_constraint :orders, name: "orders_complete_contact_required"
    remove_check_constraint :orders, name: "orders_pending_contact_unshipped"
    remove_check_constraint :orders, name: "orders_import_contact_issues_valid"
    %i[customer_id customer_name customer_phone customer_city customer_address].each do |column|
      change_column_null :orders, column, false
    end
    remove_column :orders, :import_contact_issues
  end
end
