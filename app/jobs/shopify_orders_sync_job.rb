# frozen_string_literal: true

# Registers the Shopify order webhook and imports recent COD orders. Runs once
# right after a merchant authorizes the app, then on the schedule in
# config/schedule.yml as a safety net for missed webhooks.
class ShopifyOrdersSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id = nil)
    scope = StoreConnection.where(provider: "shopify", active: true, shopify_oauth: true)
    scope = scope.where(id: connection_id) if connection_id
    scope.find_each do |connection|
      result = Connections::ShopifyOrderSync.new(connection).call
      Rails.logger.info("[ShopifyOrdersSyncJob] connection=#{connection.id} imported=#{result.imported} rejected=#{result.rejected} replayed=#{result.replayed} complete=#{result.complete}")
    rescue Connections::ShopifyApi::Error => error
      Rails.logger.warn("[ShopifyOrdersSyncJob] connection=#{connection.id} error=#{error.code}")
    rescue Connections::WebhookIntake::Error => error
      Rails.logger.warn("[ShopifyOrdersSyncJob] connection=#{connection.id} intake=#{error.message}")
    end
  end
end
