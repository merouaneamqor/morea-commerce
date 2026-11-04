# frozen_string_literal: true

require "uri"

module MetaAds
  # Browser half of Facebook Login for Business. The single redirect URI lives on the platform apex, so the
  # state is a signed, expiring token naming the store and user, plus a random nonce that is also kept in the
  # session (shared across the apex and store hosts) and as a SHA-256 digest on the store's connection.
  # The callback accepts it once: signature, expiry, session, user, store and digest must all agree.
  class Oauth
    LIFETIME = 10.minutes
    PURPOSE = "meta-ads-oauth-state"

    class Error < StandardError
      CODES = %w[config_missing invalid_state authorization_expired authorization_denied authorization_failed missing_scopes unavailable].freeze
      attr_reader :code

      def initialize(code)
        @code = CODES.include?(code) ? code : "authorization_failed"
        super("Meta authorization: #{@code}")
      end
    end

    # What the callback learned from a valid state, even when Meta reported a refusal.
    Pending = Struct.new(:store, :user, :connection, :nonce, keyword_init: true)

    def self.configured?
      Config.configured?
    end

    # Creates a token-less placeholder connection on first use so the state digest has a row to live on.
    def self.authorization_url(store:, session:, user_id:)
      raise Error.new("config_missing") unless configured?

      nonce = SecureRandom.hex(32)
      connection = find_or_create_connection(store)
      connection.with_lock do
        connection.update!(oauth_state_digest: Digest::SHA256.hexdigest(nonce), oauth_state_expires_at: LIFETIME.from_now)
      end
      session[:meta_ads_oauth] = { "nonce" => nonce, "store_id" => store.id, "user_id" => user_id }
      state = verifier.generate({ "n" => nonce, "s" => store.id, "u" => user_id }, expires_in: LIFETIME, purpose: PURPOSE)
      query = URI.encode_www_form(client_id: Config.app_id, redirect_uri: Config.redirect_uri, state: state,
        config_id: Config.login_config_id, response_type: "code", override_default_response_type: "true")
      "https://www.facebook.com/#{Config.api_version}/dialog/oauth?#{query}"
    end

    # Validates the state of a callback and returns a Pending. Does not call Meta and does not consume the
    # single-use nonce; call consume! once Meta's answer is known to be a code.
    def self.pending_for(params:, session:)
      raise Error.new("config_missing") unless configured?

      stored = session[:meta_ads_oauth]
      payload = verifier.verified(params[:state].to_s, purpose: PURPOSE)
      raise Error.new("invalid_state") unless payload.is_a?(Hash) && stored.is_a?(Hash)
      raise Error.new("invalid_state") unless payload["s"] == stored["store_id"] && payload["u"] == stored["user_id"] &&
        ActiveSupport::SecurityUtils.secure_compare(payload["n"].to_s, stored["nonce"].to_s)

      store = Store.find_by(id: payload["s"])
      user = store&.users&.active&.find_by(id: payload["u"]) || User.super_admins.active.find_by(id: payload["u"])
      connection = store && MetaAds::Connection.find_by(store_id: store.id)
      raise Error.new("invalid_state") unless store && user && connection

      Pending.new(store: store, user: user, connection: connection, nonce: payload["n"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Error.new("invalid_state")
    end

    # Single use: burns the nonce and returns the authorization code.
    def self.consume!(pending:, params:, session:)
      session.delete(:meta_ads_oauth)
      raise Error.new("authorization_denied") if params[:error].present? || params[:error_reason].present?

      code = params[:code].to_s
      raise Error.new("authorization_failed") unless code.present? && code.bytesize <= 4096 && !code.match?(/[\r\n]/)

      connection = pending.connection
      connection.with_lock do
        unless connection.oauth_state_expires_at&.future? && connection.oauth_state_digest.present? &&
            ActiveSupport::SecurityUtils.secure_compare(connection.oauth_state_digest, Digest::SHA256.hexdigest(pending.nonce))
          raise Error.new("authorization_expired")
        end
        connection.update!(oauth_state_digest: nil, oauth_state_expires_at: nil)
      end
      code
    end

    def self.verifier
      Rails.application.message_verifier("meta-ads-oauth")
    end
    private_class_method :verifier

    def self.find_or_create_connection(store)
      MetaAds::Connection.find_by(store_id: store.id) || MetaAds::Connection.create!(store: store, status: "disconnected")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      MetaAds::Connection.find_by!(store_id: store.id)
    end
    private_class_method :find_or_create_connection
  end
end
