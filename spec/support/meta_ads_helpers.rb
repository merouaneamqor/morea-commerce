# frozen_string_literal: true

# Shared helpers for the Meta Ads specs. Nothing here talks to Meta: every Graph call goes through a transport lambda.
module MetaAdsHelpers
  META_ENV = {
    "META_APP_ID" => "synthetic-app-id", "META_APP_SECRET" => "synthetic-app-secret",
    "META_LOGIN_CONFIG_ID" => "synthetic-config-id", "META_REDIRECT_URI" => "http://lvh.me/auth/meta/callback"
  }.freeze

  def stub_meta_env(overrides = {})
    allow(ENV).to receive(:[]).and_call_original
    META_ENV.merge(overrides).each { |key, value| allow(ENV).to receive(:[]).with(key).and_return(value) }
  end

  def meta_reply(body = nil, status: 200, headers: {}, **fields)
    Struct.new(:code, :body, :to_hash).new(status.to_s, (body || fields).to_json, headers)
  end

  # Signed request as Meta sends it to the data deletion callback.
  def meta_signed_request(payload, secret: "synthetic-app-secret")
    encoded = Base64.urlsafe_encode64(payload.to_json).delete("=")
    "#{Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, encoded)).delete("=")}.#{encoded}"
  end
end

RSpec.configure { |config| config.include MetaAdsHelpers }
