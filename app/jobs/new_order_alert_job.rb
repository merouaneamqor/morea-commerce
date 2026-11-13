class NewOrderAlertJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    Notifications::OrderAlert.new(order).deliver if order
  end
end
