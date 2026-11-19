module Connections
  # Compatibility for older callers. No Shopify billing requests or entitlement
  # updates are performed. Historical subscription columns remain untouched.
  class SealloEntitlement
    def self.refresh!(connection)
      return unless connection.shopify_app == "seallo_connect"

      true
    end
  end
end
