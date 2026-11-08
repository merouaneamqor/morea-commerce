# frozen_string_literal: true

class AmeexPollJob < ApplicationJob
  queue_as :default

  def perform
    total = 0
    Store.with_ameex.find_each do |store|
      count = if store.ships_with?(:ameex)
        Ameex::Sync.enqueue_all(store.orders)
      else
        Ameex::Sync.reapply_stored!(store.orders)
        _, to_refresh = Ameex::Sync.pending_orders(store.orders)
        to_refresh.find_each { |o| AmeexSyncJob.perform_later(o.id, "refresh") }
        to_refresh.count
      end
      total += count
      Rails.logger.info("[AmeexPollJob] store=#{store.slug} queued #{count} orders")
    end
    Rails.logger.info("[AmeexPollJob] queued #{total} orders total")
  end
end
