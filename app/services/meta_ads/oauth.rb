# frozen_string_literal: true

require "uri"

module MetaAds
  # Browser half of Meta Login. Mirrors Connections::ShopifyOauth: a random state bound to the
  # session, store and user, stored as a SHA-256 digest on the store's connection, single use, 10 minutes.
  class Oauth
    LIFETIME = 10.minutes

    class Error < StandardError
      CODES = %w[config_missing invalid_state authorization_expired authorization_denied authorization_failed missing_scopes unavailable].freeze
      attr_reader :code

      def initialize(code)
        @code = CODES.include?(code) ? code : "authorization_failed"
        super("Meta authorization: #{@code}")
      end
    end

    def self.configured?
      Config.configured?
    end

    # Creates a token-less placeholder connection on first use so the state digest has a row to live on.
    def self.authorization_url(store:, session:, user_id:, callback_url:)
      raise Error.new("config_missing") unless configured?

      nonce = SecureRandom.hex(32)
      connection = find_or_create_connection(store)
      connection.with_lock do
        connection.update!(oauth_state_digest: Digest::SHA256.hexdigest(nonce), oauth_state_expires_at: LIFETIME.from_now)
      end
      session[:meta_ads_oauth] = { "state" => nonce, "store_id" => store.id, "user_id" => user_id }
      query = URI.encode_www_form(client_id: Config.app_id, redirect_uri: callback_url, state: nonce,
        scope: Config::SCOPES.join(","), response_type: "code")
      "https://www.facebook.com/#{Config.api_version}/dialog/oauth?#{query}"
    end

    # Validates state and returns [connection, code]. Does not call Meta.
    def self.consume_callback!(params:, session:, store:, user_id:)
      raise Error.new("config_missing") unless configured?

      pending = session.delete(:meta_ads_oauth)
      state = params[:state].to_s
      unless pending.is_a?(Hash) && pending["store_id"] == store.id && pending["user_id"] == user_id &&
          state.match?(/\A[0-9a-f]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, state)
        raise Error.new("invalid_state")
      end
      raise Error.new("authorization_denied") if params[:error].present?

      code = params[:code].to_s
      raise Error.new("authorization_failed") unless code.present? && code.bytesize <= 4096 && !code.match?(/[\r\n]/)

      connection = MetaAds::Connection.find_by(store_id: store.id)
      raise Error.new("invalid_state") unless connection

      connection.with_lock do
        unless connection.oauth_state_expires_at&.future? && connection.oauth_state_digest.present? &&
            ActiveSupport::SecurityUtils.secure_compare(connection.oauth_state_digest, Digest::SHA256.hexdigest(state))
          raise Error.new("authorization_expired")
        end
        connection.update!(oauth_state_digest: nil, oauth_state_expires_at: nil)
      end
      [ connection, code ]
    end

    def self.find_or_create_connection(store)
      MetaAds::Connection.find_by(store_id: store.id) || MetaAds::Connection.create!(store: store, status: "disconnected")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      MetaAds::Connection.find_by!(store_id: store.id)
    end
    private_class_method :find_or_create_connection
  end
end
