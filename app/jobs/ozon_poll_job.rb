# frozen_string_literal: true

# Clock job (sidekiq-cron): refresh parcels still moving and retry confirmed orders not yet on Ozon.
class OzonPollJob < ApplicationJob
  queue_as :default

  def perform
    total = 0
    Store.with_ozon.find_each do |store|
      count = if store.ships_with?(:ozon)
        Ozon::Sync.enqueue_all(store.orders)
      else
        # Default courier is elsewhere — only refresh parcels already on Ozon.
        Ozon::Sync.reapply_stored!(store.orders)
        _, to_refresh = Ozon::Sync.pending_orders(store.orders)
        to_refresh.find_each { |o| OzonSyncJob.perform_later(o.id, "refresh") }
        to_refresh.count
      end
      total += count
      Rails.logger.info("[OzonPollJob] store=#{store.slug} queued #{count} orders")
    end
    Rails.logger.info("[OzonPollJob] queued #{total} orders total")
  end
end
