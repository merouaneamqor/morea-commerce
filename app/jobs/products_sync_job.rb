# frozen_string_literal: true

# Reads the catalog of connected stores into the workspace's products (Connections::ProductImport). With a connection id it
# syncs that one (the button on its page); without, every active connection that has what its platform needs (the schedule).
# A failed run is already written on the connection (state and error code), so it is not retried blindly.
class ProductsSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id = nil)
    scope = StoreConnection.where(active: true)
    scope = scope.where(id: connection_id) if connection_id
    scope.find_each do |connection|
      next unless connection.products_importable?

      Connections::ProductImport.new(connection: connection).call
    rescue Connections::ProductSources::Error
      next
    end
  end
end
