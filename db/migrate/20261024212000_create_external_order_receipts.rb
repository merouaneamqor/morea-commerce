class CreateExternalOrderReceipts < ActiveRecord::Migration[8.0]
  def change
    create_table :external_order_receipts do |t|
      t.references :store_connection, null: false, foreign_key: true
      t.references :order, foreign_key: true, index: { unique: true }
      t.string :external_id, null: false
      t.string :status, null: false
      t.string :error_code
      t.datetime :received_at, null: false
      t.timestamps
    end
    add_index :external_order_receipts, %i[store_connection_id external_id], unique: true, name: "index_external_receipts_on_connection_identity"
    add_check_constraint :external_order_receipts, "(status = 'accepted' AND order_id IS NOT NULL AND error_code IS NULL) OR (status = 'rejected' AND order_id IS NULL AND error_code IS NOT NULL)", name: "external_receipt_result"
  end
end
