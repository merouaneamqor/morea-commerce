# frozen_string_literal: true

# Clock job (sidekiq-cron, see config/schedule.yml): fan out a refresh for every
# parcel still moving or coming back, and retry confirmed orders not yet on Sendit
class SenditPollJob < ApplicationJob
  queue_as :default

  def perform
    total = 0
    Store.with_sendit.find_each do |store|
      count = Sendit::Sync.enqueue_all(store.orders)
      total += count
      Rails.logger.info("[SenditPollJob] store=#{store.slug} queued #{count} orders")
    end
    Rails.logger.info("[SenditPollJob] queued #{total} orders total")
  end
end
