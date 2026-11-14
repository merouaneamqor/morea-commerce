# An attribution is a durable "this order is for this agent", set by an owner or a supervisor (or by the automatic attribution). It is not the
# claim (assigned_user_id): a claim is a short lock taken while someone works the order and expires after 15 minutes without activity; an
# attribution stays until it is changed or the order leaves the queue. Other agents do not see an order attributed to someone else.
class AddAttributionToOrderConfirmations < ActiveRecord::Migration[8.1]
  def change
    add_reference :order_confirmations, :attributed_user, foreign_key: { to_table: :users, on_delete: :nullify }, index: true, null: true
    add_column :order_confirmations, :attributed_at, :datetime
  end
end
