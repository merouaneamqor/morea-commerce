# frozen_string_literal: true

class AddPaymentReferenceToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :payment_reference, :string
  end
end
