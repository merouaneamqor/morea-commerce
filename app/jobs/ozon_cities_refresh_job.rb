# frozen_string_literal: true

# Fetches Ozon's city list after connect and weekly for every workspace with Ozon.
class OzonCitiesRefreshJob < ApplicationJob
  queue_as :default

  def perform(store_id = nil)
    stores = store_id ? Store.where(id: store_id) : Store.with_ozon
    stores.find_each { |store| refresh(store) }
  end

  private

  def refresh(store)
    count = Ozon::Cities.refresh!(store: store)
    store.delivery_accounts.where(provider: "ozon", is_active: true).update_all(cities_count: count, cities_synced_at: Time.current)
    Rails.logger.info("[OzonCitiesRefreshJob] store=#{store.slug} cities=#{count}")
  rescue Ozon::Client::Error => e
    Rails.logger.warn("[OzonCitiesRefreshJob] store=#{store.slug} failed: #{e.message}")
  end
end
