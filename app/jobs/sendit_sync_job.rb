# frozen_string_literal: true

class SenditSyncJob < ApplicationJob
  queue_as :default

  ACTIONS = %w[push refresh cancel].freeze

  def perform(order_id, action = "refresh")
    order = Order.includes(:order_items).find_by(id: order_id)
    return unless order && ACTIONS.include?(action) && Sendit::Client.configured?

    Sendit::Sync.new(order).public_send("#{action}!")
  end
end
