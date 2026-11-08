# frozen_string_literal: true

class OzonSyncJob < ApplicationJob
  queue_as :default

  ACTIONS = %w[push refresh cancel].freeze

  def perform(order_id, action = "refresh")
    order = Order.includes(:order_items, :store).find_by(id: order_id)
    return unless order && ACTIONS.include?(action) && order.store.ozon_configured?

    Ozon::Sync.new(order).public_send("#{action}!")
  end
end
