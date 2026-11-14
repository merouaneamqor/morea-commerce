# Sends the store's automatic WhatsApp message for a new order (Whatsapp::OrderMessenger). The order may be gone or already messaged by the time it runs.
class WhatsappOrderMessageJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order

    Whatsapp::OrderMessenger.new(order).deliver_new_order!
  end
end
