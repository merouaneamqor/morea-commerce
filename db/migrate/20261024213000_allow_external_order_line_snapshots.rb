class AllowExternalOrderLineSnapshots < ActiveRecord::Migration[8.0]
  def up
    change_column_null :order_items, :product_id, true
  end

  def down
    if select_value("SELECT COUNT(*) FROM order_items WHERE product_id IS NULL").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "External order snapshots must be mapped before restoring NOT NULL."
    end

    change_column_null :order_items, :product_id, false
  end
end
