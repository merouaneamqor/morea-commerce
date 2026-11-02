# frozen_string_literal: true

# Daily retention sweep for Seallo Connect imports; schedule in config/schedule.yml.
class SealloRetentionJob < ApplicationJob
  queue_as :default

  def perform
    count = Connections::SealloRetention.call
    Rails.logger.info("seallo_retention redacted_orders=#{count}")
  end
end
