# frozen_string_literal: true

module MetaAds
  # Server half of Meta Login: exchanges the code for a long-lived user token, checks granted scopes
  # and stores the encrypted token on the store's connection. The caller has already validated state.
  class Authorizer
    def initialize(connection:, redirect_uri:, transport: nil)
      @connection = connection
      @redirect_uri = redirect_uri
      @transport = transport
    end

    def authorize!(code:)
      raise Oauth::Error.new("config_missing") unless Config.configured?

      app = Client.new(token: "#{Config.app_id}|#{Config.app_secret}", transport: @transport)
      short = exchange(app, code: code, redirect_uri: @redirect_uri)
      long = exchange(app, grant_type: "fb_exchange_token", fb_exchange_token: short.fetch("access_token"))
      token = long["access_token"].presence || short.fetch("access_token")
      info = app.get("debug_token", input_token: token).data.first.to_h["data"]
      raise Oauth::Error.new("authorization_failed") unless info.is_a?(Hash)

      scopes = Array(info["scopes"]).map(&:to_s)
      raise Oauth::Error.new("authorization_failed") unless info["is_valid"] == true
      raise Oauth::Error.new("missing_scopes") unless (Config::SCOPES - scopes).empty?

      expires_at = info["expires_at"].to_i.positive? ? Time.at(info["expires_at"].to_i).utc : nil
      expires_at ||= Time.current + long["expires_in"].to_i if long["expires_in"].to_i.positive?
      @connection.with_lock do
        @connection.update!(status: "active", access_token: token, token_expires_at: expires_at, granted_scopes: scopes,
          meta_user_id: info["user_id"].presence&.to_s, last_verified_at: Time.current, last_error_code: nil)
      end
      @connection
    rescue Client::RateLimitError, Client::TransientError
      raise Oauth::Error.new("unavailable")
    rescue Client::Error, KeyError
      raise Oauth::Error.new("authorization_failed")
    end

    private

    def exchange(app, **extra)
      body = { client_id: Config.app_id, client_secret: Config.app_secret }.merge(extra)
      app.post("oauth/access_token", body).data.first.to_h
    end
  end
end
