class OrderStatusJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order

    Rails.logger.info("[OrderStatusJob] Order #{order.number} is now #{order.status}")
    # Stub for SMS / email notification to the customer.
  end
end
