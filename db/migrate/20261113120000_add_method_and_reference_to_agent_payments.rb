# How an agent was paid (cash or bank transfer) and a reference; the proof itself is an Active Storage attachment. Payments made before this
# existed keep a NULL method.
class AddMethodAndReferenceToAgentPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_payments, :payment_method, :string
    add_column :agent_payments, :reference, :string
    add_check_constraint :agent_payments, "payment_method IS NULL OR payment_method IN ('cash', 'bank_transfer')", name: "agent_payments_method"
    add_check_constraint :agent_payments, "reference IS NULL OR char_length(reference::text) <= 200", name: "agent_payments_reference_length"
  end
end
