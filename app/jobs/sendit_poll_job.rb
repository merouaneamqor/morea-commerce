# frozen_string_literal: true

# Clock job (sidekiq-cron, see config/schedule.yml): fan out a refresh for every
# parcel still moving or coming back, and retry confirmed orders not yet on Sendit
class SenditPollJob < ApplicationJob
  queue_as :default

  def perform
    return unless Sendit::Client.configured?

    count = Sendit::Sync.enqueue_all
    Rails.logger.info("[SenditPollJob] queued #{count} orders")
  end
end
