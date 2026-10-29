# frozen_string_literal: true

module Connections
  # The caller supplies an authorized workspace. Credentials are checked only
  # for presence here; the background sync owns token refresh and API errors.
  class ShopifySyncRequest
    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super("Shopify sync: #{code}")
      end
    end

    def self.call(store:, connection_id: nil)
      raise ActiveRecord::RecordNotFound unless store

      if connection_id.present?
        connection = store.store_connections.find(connection_id)
        raise Error.new("credentials_missing") unless connection.shopify_api_configured?
        raise Error.new("disconnected") unless connection.active?
        unless connection.shopify_access_token_ciphertext.present? || connection.shopify_refresh_token_ciphertext.present?
          raise Error.new("credentials_missing")
        end

        ShopifyOrdersSyncJob.perform_later(connection.id)
        return 1
      end

      scope = store.store_connections.where(provider: "shopify", active: true, shopify_oauth: true)
      ready = scope.where.not(shopify_access_token_ciphertext: [ nil, "" ])
        .or(scope.where.not(shopify_refresh_token_ciphertext: [ nil, "" ]))
      count = 0
      ready.find_each do |connection|
        ShopifyOrdersSyncJob.perform_later(connection.id)
        count += 1
      end
      raise Error.new("credentials_missing") if count.zero?

      count
    end
  end
end
