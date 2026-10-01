# frozen_string_literal: true

class DiscordOrderNotifyJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    order = Order.includes(:order_items, :store).find_by(id: order_id)
    return unless order

    DiscordNotifier.notify_new_order(order)
  end
end
