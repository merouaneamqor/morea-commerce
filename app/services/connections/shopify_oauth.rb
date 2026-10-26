# frozen_string_literal: true

require "openssl"
require "uri"

module Connections
  class ShopifyOauth
    SCOPES = %w[write_orders read_orders read_customers read_products].freeze
    LIFETIME = 10.minutes

    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super("Shopify authorization: #{code}")
      end
    end

    def self.configured?
      ENV["SHOPIFY_CLIENT_ID"].present? && ENV["SHOPIFY_CLIENT_SECRET"].present?
    end

    def self.authorization_url(connection:, session:, user_id:, callback_url:)
      raise Error.new("config_missing") unless configured?
      raise Error.new("disconnected") unless connection.active? && connection.provider == "shopify"

      nonce = SecureRandom.hex(32)
      connection.with_lock do
        connection.update!(shopify_oauth_state_digest: Digest::SHA256.hexdigest(nonce), shopify_oauth_state_expires_at: LIFETIME.from_now)
      end
      session[:shopify_oauth] = { "state" => nonce, "store_id" => connection.store_id, "connection_id" => connection.id,
        "user_id" => user_id, "shop" => connection.external_domain }
      query = URI.encode_www_form(client_id: ENV["SHOPIFY_CLIENT_ID"], scope: SCOPES.join(","),
        redirect_uri: callback_url, state: nonce)
      "https://#{connection.external_domain}/admin/oauth/authorize?#{query}"
    end

    def self.consume_callback!(query_string:, session:, store:, user_id:)
      raise Error.new("config_missing") unless configured?
      raise Error.new("invalid_signature") if query_string.bytesize > 16_384

      pairs = URI.decode_www_form(query_string)
      raise Error.new("invalid_signature") unless pairs.map(&:first).uniq.length == pairs.length

      query = pairs.to_h
      signature = query.delete("hmac").to_s
      query.delete("signature")
      expected = OpenSSL::HMAC.hexdigest("sha256", ENV["SHOPIFY_CLIENT_SECRET"], URI.encode_www_form(query.sort))
      unless signature.match?(/\A[0-9a-f]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        raise Error.new("invalid_signature")
      end
      timestamp = query["timestamp"].to_s
      unless timestamp.match?(/\A\d{1,12}\z/) && timestamp.to_i.between?(LIFETIME.ago.to_i, 1.minute.from_now.to_i)
        raise Error.new("authorization_expired")
      end
      pending = session.delete(:shopify_oauth)
      unless pending.is_a?(Hash) && pending["store_id"] == store.id && pending["user_id"] == user_id &&
          pending["shop"] == query["shop"] && query["state"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
          ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, query["state"])
        raise Error.new("invalid_state")
      end
      code = query["code"].to_s
      raise Error.new("authorization_failed") unless code.present? && code.bytesize <= 4096 && !code.match?(/[\r\n]/)

      connection = store.store_connections.find_by(id: pending["connection_id"], provider: "shopify", external_domain: query["shop"])
      raise Error.new("invalid_state") unless connection

      connection.with_lock do
        digest = Digest::SHA256.hexdigest(query["state"])
        unless connection.active? && connection.shopify_oauth_state_expires_at&.future? &&
            connection.shopify_oauth_state_digest.present? && ActiveSupport::SecurityUtils.secure_compare(connection.shopify_oauth_state_digest, digest)
          raise Error.new("invalid_state")
        end
        connection.update!(shopify_oauth: true, shopify_oauth_state_digest: nil, shopify_oauth_state_expires_at: nil)
      end
      [ connection, code ]
    rescue ArgumentError
      raise Error.new("invalid_signature")
    end
  end
end
