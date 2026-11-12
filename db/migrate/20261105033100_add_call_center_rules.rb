# frozen_string_literal: true

# Rules of the agent call center.
# - order_confirmations.last_activity_at: a claim with no activity for 15 minutes is released automatically.
# - disposition "blocked": a new order from a blocked number does not enter the queue (tab "Bloqués").
# - blocked_phones: per-store list of blocked numbers (digits key, reason, who, when).
# - users.return_penalty_cents: per-agent penalty deducted when an order the agent confirmed ends up returned.
# - agent_deductions: one pending deduction per returned order, subtracted at the next payout.
# - agent_payments.deductions_cents: the deductions that payout subtracted (cash paid = amount - deductions).
class AddCallCenterRules < ActiveRecord::Migration[8.0]
  DISPOSITIONS = %w[pending no_answer callback confirmed cancelled wrong_number].freeze

  def up
    add_column :order_confirmations, :last_activity_at, :datetime
    remove_check_constraint :order_confirmations, name: "confirmation_disposition"
    add_check_constraint :order_confirmations, "disposition IN (#{(DISPOSITIONS + %w[blocked]).map { |v| connection.quote(v) }.join(', ')})", name: "confirmation_disposition"

    add_column :users, :return_penalty_cents, :integer, default: 0, null: false
    add_check_constraint :users, "return_penalty_cents >= 0", name: "users_return_penalty_nonnegative"

    add_column :agent_payments, :deductions_cents, :bigint, default: 0, null: false
    add_check_constraint :agent_payments, "deductions_cents >= 0 AND deductions_cents <= amount_cents", name: "agent_payments_deductions_within_amount"

    create_table :agent_deductions do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true, index: { unique: true }
      t.references :agent_payment, foreign_key: { on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
      t.check_constraint "amount_cents > 0", name: "agent_deductions_amount_positive"
      t.check_constraint "status IN ('pending', 'applied')", name: "agent_deductions_status"
      t.index %i[store_id user_id status]
    end

    create_table :blocked_phones do |t|
      t.references :store, null: false, foreign_key: true
      t.string :phone_key, null: false
      t.string :reason, null: false
      t.references :blocked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[store_id phone_key], unique: true
    end
  end

  def down
    drop_table :blocked_phones
    drop_table :agent_deductions
    remove_check_constraint :agent_payments, name: "agent_payments_deductions_within_amount"
    remove_column :agent_payments, :deductions_cents
    remove_check_constraint :users, name: "users_return_penalty_nonnegative"
    remove_column :users, :return_penalty_cents
    remove_check_constraint :order_confirmations, name: "confirmation_disposition"
    add_check_constraint :order_confirmations, "disposition IN (#{DISPOSITIONS.map { |v| connection.quote(v) }.join(', ')})", name: "confirmation_disposition"
    remove_column :order_confirmations, :last_activity_at
  end
end
