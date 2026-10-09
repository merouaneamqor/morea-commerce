# frozen_string_literal: true

class ExpandOrderStatuses < ActiveRecord::Migration[8.1]
  def up
    # Closest Sendit equivalent for the old coarse "shipped" bucket
    execute <<~SQL.squish
      UPDATE orders SET status = 'in_transit' WHERE status = 'shipped'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE orders
      SET status = 'shipped'
      WHERE status IN (
        'awaiting_pickup', 'picked_up', 'in_transit', 'out_for_delivery',
        'unreachable', 'postponed', 'address_issue'
      )
    SQL
  end
end
