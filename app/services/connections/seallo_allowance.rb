# frozen_string_literal: true

module Connections
  # Seallo Connect no longer enforces a Shopify (or Connect-specific) imported-
  # order allowance. Intake still serializes under the connection lock and keeps
  # receipt replay / idempotency. Workspace platform access remains
  # Store#operational_access? at the webhook/import gates.
  class SealloAllowance
    def self.check!(_connection)
      nil
    end

    def self.used(_connection)
      0
    end
  end
end
