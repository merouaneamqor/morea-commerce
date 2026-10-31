module Connections
  class SealloConnect
    class Error < StandardError; end

    def self.call(code:, shop:)
      raise Error, "invalid_code" unless code.to_s.match?(/\A[0-9a-f]{48}\z/)
      raise Error, "invalid_shop" unless shop.to_s.bytesize <= 253 && shop.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)

      pending = SealloConnectionCode.find_by(digest: Digest::SHA256.hexdigest(code))
      raise Error, "invalid_code" unless pending

      connection = nil
      pending.with_lock do
        user = pending.user.reload
        store = pending.store
        unless pending.consumed_at.nil? && pending.expires_at.future? && user.active? &&
            (user.super_admin? || (user.admin? && user.store_id == store.id))
          raise Error, "invalid_code"
        end
        connection = StoreConnection.find_by(shopify_app: "seallo_connect", external_domain: shop)
        raise Error, "already_linked" if connection && connection.store_id != store.id
        connection ||= store.store_connections.find_by(provider: "shopify", external_domain: shop)
        raise Error, "existing_connection" if connection && connection.shopify_app != "seallo_connect"

        connection ||= store.store_connections.new(provider: "shopify", external_domain: shop, name: "Seallo Connect · #{shop}", shopify_oauth: true, shopify_app: "seallo_connect")
        connection.active = true
        connection.save!
        raise Error, "subscription_required" unless SealloEntitlement.refresh!(connection)
        ShopifyApi.new(connection: connection).verify!
        pending.update!(consumed_at: Time.current)
      end
      ShopifyOrdersSyncJob.perform_later(connection.id)
      connection
    rescue ActiveRecord::RecordNotUnique
      raise Error, "already_linked"
    end
  end
end
