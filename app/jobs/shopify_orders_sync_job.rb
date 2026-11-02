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
      if connection.shopify_app == "seallo_connect"
        begin
          unless Connections::SealloEntitlement.refresh!(connection)
            connection.update!(shopify_sync_state: "failed", shopify_sync_error: "subscription_required")
            next
          end
        rescue Connections::SealloBridge::Error => error
          connection.update!(shopify_sync_state: "failed", shopify_sync_error: error.message)
          next
        end
      end
      next unless connection.store.operational_access?

      # Commit the start marker before the long-running import transaction so
      # status reads can show progress while the connection lock is held.
      connection.update!(shopify_sync_state: "running", shopify_sync_started_at: Time.current, shopify_sync_error: nil)
      # Serialize overlapping manual/scheduled jobs and cursor updates. Imports
      # already serialize on this same connection and retain receipt identities.
      connection.with_lock do
        next unless connection.active? && connection.store.operational_access?

        begin
          result = Connections::ShopifyOrderSync.new(connection).call
          connection.update!(shopify_sync_state: result.complete ? "complete" : "catching_up", shopify_sync_finished_at: Time.current,
            shopify_sync_counts: { imported: result.imported, rejected: result.rejected, replayed: result.replayed })
        rescue Connections::ShopifyApi::Error => error
          connection.update!(shopify_sync_state: "failed", shopify_sync_error: error.code, shopify_sync_finished_at: Time.current)
        rescue Connections::WebhookIntake::Error => error
          connection.update!(shopify_sync_state: "failed", shopify_sync_error: error.message, shopify_sync_finished_at: Time.current)
        end
      end
    end
  end
end
