# frozen_string_literal: true

# Call panel of the confirmation desk.
# - order_confirmations.call_started_at: set when an agent opens the call panel on an order; the server measures
#   the call from it (the browser timer is only a display).
# - confirmation_attempts.call_seconds: duration of the call, measured by the server when the call is finished.
# - outcomes "wrong_number" (Numéro erroné) and "abandoned" (panel closed after more than 5 seconds, no result).
# - orders.second_phone: optional second number given by the customer, editable in the panel.
class AddCallPanelFields < ActiveRecord::Migration[8.0]
  OLD_OUTCOMES = %w[no_answer callback confirmed cancelled].freeze
  NEW_OUTCOMES = (OLD_OUTCOMES + %w[wrong_number abandoned]).freeze
  OLD_DISPOSITIONS = %w[pending no_answer callback confirmed cancelled].freeze
  NEW_DISPOSITIONS = (OLD_DISPOSITIONS + %w[wrong_number]).freeze

  def up
    add_column :order_confirmations, :call_started_at, :datetime
    add_column :confirmation_attempts, :call_seconds, :integer
    add_check_constraint :confirmation_attempts, "call_seconds IS NULL OR call_seconds >= 0", name: "confirmation_attempt_call_seconds_nonnegative"
    add_column :orders, :second_phone, :string, limit: 30
    swap_checks(:confirmation_attempts, "confirmation_attempt_outcome", "outcome", NEW_OUTCOMES)
    swap_checks(:order_confirmations, "confirmation_disposition", "disposition", NEW_DISPOSITIONS)
  end

  def down
    swap_checks(:order_confirmations, "confirmation_disposition", "disposition", OLD_DISPOSITIONS)
    swap_checks(:confirmation_attempts, "confirmation_attempt_outcome", "outcome", OLD_OUTCOMES)
    remove_column :orders, :second_phone
    remove_check_constraint :confirmation_attempts, name: "confirmation_attempt_call_seconds_nonnegative"
    remove_column :confirmation_attempts, :call_seconds
    remove_column :order_confirmations, :call_started_at
  end

  private

  def swap_checks(table, name, column, values)
    remove_check_constraint table, name: name
    add_check_constraint table, "#{column} IN (#{values.map { |v| connection.quote(v) }.join(', ')})", name: name
  end
end
