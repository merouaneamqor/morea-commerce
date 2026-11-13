# frozen_string_literal: true

module Connections
  # Shopify connections are created only through Seallo Connect. This module now
  # answers one question for existing standalone connections: whether the shared
  # app credentials needed for their sync are configured. Its authorization
  # helpers were removed with the standalone connect route.
  class ShopifyOauth
    def self.configured?
      ENV["SHOPIFY_CLIENT_ID"].present? && ENV["SHOPIFY_CLIENT_SECRET"].present?
    end
  end
end
