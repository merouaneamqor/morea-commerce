# frozen_string_literal: true

class AmeexCitiesRefreshJob < ApplicationJob
  queue_as :default

  def perform(store_id = nil)
    stores = store_id ? Store.where(id: store_id) : Store.with_ameex
    stores.find_each { |store| refresh(store) }
  end

  private

  def refresh(store)
    count = Ameex::Cities.refresh!(store: store)
    Ameex::Sync.refresh_labels!(store)
    store.delivery_accounts.where(provider: "ameex", is_active: true).update_all(cities_count: count, cities_synced_at: Time.current)
    Rails.logger.info("[AmeexCitiesRefreshJob] store=#{store.slug} cities=#{count}")
  rescue Ameex::Client::Error => e
    Rails.logger.warn("[AmeexCitiesRefreshJob] store=#{store.slug} failed: #{e.message}")
  end
end
