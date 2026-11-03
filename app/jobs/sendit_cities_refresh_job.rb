# frozen_string_literal: true

# Fetches Sendit's city list. Run for one workspace right after it connects Sendit, and for every
# workspace with Sendit once a week (sidekiq-cron, see config/schedule.yml).
class SenditCitiesRefreshJob < ApplicationJob
  queue_as :default

  def perform(store_id = nil)
    stores = store_id ? Store.where(id: store_id) : Store.with_sendit
    stores.find_each { |store| refresh(store) }
  end

  private

  def refresh(store)
    counts = Sendit::Districts.refresh!(store: store)
    store.delivery_accounts.where(provider: "sendit", is_active: true).update_all(cities_count: counts[:districts], cities_synced_at: Time.current)
    Rails.logger.info("[SenditCitiesRefreshJob] store=#{store.slug} districts=#{counts[:districts]} pickup_cities=#{counts[:pickup_cities]}")
  rescue Sendit::Client::Error => e
    Rails.logger.warn("[SenditCitiesRefreshJob] store=#{store.slug} failed: #{e.message}")
  end
end
