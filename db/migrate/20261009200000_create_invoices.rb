# frozen_string_literal: true

class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      t.references :store, null: false, foreign_key: true
      t.string :number, null: false
      t.string :status, null: false, default: "draft"
      t.integer :amount_cents, null: false, default: 0
      t.string :billing_interval, null: false
      t.date :period_starts_on, null: false
      t.date :period_ends_on, null: false
      t.date :due_on
      t.datetime :issued_at
      t.datetime :paid_at
      t.text :notes

      t.timestamps
    end

    add_index :invoices, :number, unique: true
    add_index :invoices, :status
    add_index :invoices, [ :status, :due_on ]
  end
end
