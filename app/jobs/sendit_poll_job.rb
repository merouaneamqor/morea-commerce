# frozen_string_literal: true

# Clock job (sidekiq-cron, see config/schedule.yml): fan out a refresh for every
# parcel still moving or coming back, and retry confirmed orders not yet on Sendit
class SenditPollJob < ApplicationJob
  queue_as :default

  def perform
    total = 0
    Store.with_sendit.find_each do |store|
      count = if store.ships_with?(:sendit)
        Sendit::Sync.enqueue_all(store.orders)
      else
        # Default courier is elsewhere — only refresh parcels already on Sendit.
        Sendit::Sync.reapply_stored!(store.orders)
        _, to_refresh = Sendit::Sync.pending_orders(store.orders)
        to_refresh.find_each { |o| SenditSyncJob.perform_later(o.id, "refresh") }
        to_refresh.count
      end
      total += count
      Rails.logger.info("[SenditPollJob] store=#{store.slug} queued #{count} orders")
    end
    Rails.logger.info("[SenditPollJob] queued #{total} orders total")
  end
end
