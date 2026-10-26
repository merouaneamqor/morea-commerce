# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::ShopifyApi do
  # An in-memory connection keeps these transport/permission tests independent
  # of network services. Request specs cover encrypted storage and tenant records.
  let(:connection) do
    Struct.new(:provider, :active, :external_domain, :shopify_oauth,
      :shopify_access_token, :shopify_access_token_expires_at, :shopify_granted_scopes,
      :shopify_refresh_token, :shopify_refresh_token_expires_at,
      :shopify_api_verified_at, :shopify_api_error_code, keyword_init: true) do
      def active? = active
      def with_lock = yield
      def update!(attributes) = attributes.each { |key, value| public_send("#{key}=", value) }
    end.new(provider: "shopify", active: true, external_domain: "synthetic-shop.myshopify.com",
      shopify_oauth: true, shopify_refresh_token: "synthetic-old-refresh", shopify_refresh_token_expires_at: 30.days.from_now)
  end
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_ID").and_return("synthetic-shared-client")
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return("synthetic-shared-secret")
    allow(ENV).to receive(:fetch).with("SHOPIFY_CLIENT_ID").and_return("synthetic-shared-client")
    allow(ENV).to receive(:fetch).with("SHOPIFY_CLIENT_SECRET").and_return("synthetic-shared-secret")
  end
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |uri, request|
      requests << [ uri, request ]
      response = responses.shift
      raise response if response.is_a?(Exception)
      raise "Unexpected HTTP call" unless response

      response
    end
  end
  subject(:api) { described_class.new(connection: connection, transport: transport) }

  def response(status, data)
    Struct.new(:code, :body).new(status.to_s, JSON.generate(data))
  end

  def token_response
    response(200, access_token: "synthetic-token", expires_in: 3600,
      refresh_token: "synthetic-rotated-refresh", refresh_token_expires_in: 90.days.to_i)
  end

  def verification_response(domain: connection.external_domain, scopes: described_class::REQUIRED_SCOPES)
    response(200, data: { shop: { myshopifyDomain: domain },
      currentAppInstallation: { accessScopes: scopes.map { |scope| { handle: scope } } } })
  end

  def expect_failure(code)
    expect { api.verify! }.to raise_error(described_class::Error) { |error| expect(error.code).to eq(code) }
    unless described_class::TRANSIENT_ERRORS.include?(code)
      expect(connection.shopify_access_token).to be_nil
      expect(connection.shopify_refresh_token).to be_nil
    end
    expect(connection.shopify_granted_scopes).to eq([])
    expect(connection.shopify_api_verified_at).to be_nil
    expect(connection.shopify_api_error_code).to eq(code)
  end

  it "exchanges an approved authorization code and verifies identity/scopes before storing success" do
    freeze_time do
      connection.shopify_refresh_token = nil
      responses.concat([ token_response, verification_response ])
      expect(api.authorize!(code: "synthetic-code")).to be(true)
      expect(requests.first.first.to_s).to eq("https://synthetic-shop.myshopify.com/admin/oauth/access_token")
      parameters = URI.decode_www_form(requests.first.last.body).to_h
      expect(parameters).to include("code" => "synthetic-code", "expiring" => "1", "client_id" => "synthetic-shared-client")
      expect(parameters).not_to have_key("grant_type")
      expect(requests.last.first.path).to eq("/admin/api/2026-10/graphql.json")
      expect(requests.last.last["X-Shopify-Access-Token"]).to eq("synthetic-token")
      expect(connection.shopify_access_token_expires_at).to eq(1.hour.from_now)
      expect(connection.shopify_refresh_token).to eq("synthetic-rotated-refresh")
      expect(connection.shopify_refresh_token_expires_at).to eq(90.days.from_now)
      expect(connection.shopify_granted_scopes).to match_array(described_class::REQUIRED_SCOPES)
      expect(connection.shopify_api_verified_at).to eq(Time.current)
    end
  end

  it "reuses an unexpired token but rechecks permissions on explicit verification" do
    connection.shopify_access_token = "cached-token"
    connection.shopify_access_token_expires_at = 5.minutes.from_now
    responses << verification_response
    expect(api.verify!).to be(true)
    expect(requests.size).to eq(1)
    expect(requests.first.last["X-Shopify-Access-Token"]).to eq("cached-token")
  end

  it "refreshes a token inside its expiry safety window" do
    connection.shopify_access_token = "old-token"
    connection.shopify_access_token_expires_at = 30.seconds.from_now
    responses.concat([ token_response, verification_response ])
    expect(api.verify!).to be(true)
    expect(connection.shopify_access_token).to eq("synthetic-token")
    expect(URI.decode_www_form(requests.first.last.body).to_h).to include(
      "grant_type" => "refresh_token", "refresh_token" => "synthetic-old-refresh", "client_id" => "synthetic-shared-client")
  end

  it "verifies automatically before executing an internal GraphQL query" do
    responses.concat([ token_response, verification_response, response(200, data: { products: { nodes: [] } }) ])
    expect(api.graphql(query: "query { products(first: 1) { nodes { id } } }")).to eq("products" => { "nodes" => [] })
    expect(requests.length).to eq(3)
  end

  it "rejects disconnected connections without contacting Shopify" do
    connection.active = false
    expect_failure("disconnected")
    expect(requests).to be_empty
  end

  it "requires OAuth approval when there are no tokens" do
    connection.shopify_refresh_token = nil
    expect_failure("credentials_missing")
    expect(requests).to be_empty
  end

  it "requires renewed OAuth approval when the refresh token has expired" do
    connection.shopify_refresh_token_expires_at = 1.second.ago
    expect_failure("credentials_missing")
    expect(requests).to be_empty
  end

  it "rejects a connection that has not selected OAuth" do
    connection.shopify_oauth = false
    expect_failure("credentials_missing")
    expect(requests).to be_empty
  end

  it "requires the shared app configuration before contacting Shopify" do
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(nil)
    expect_failure("config_missing")
    expect(requests).to be_empty
  end

  it "rejects an arbitrary host without contacting it" do
    connection.external_domain = "127.0.0.1"
    expect_failure("source_mismatch")
    expect(requests).to be_empty
  end

  it "rejects credentials for a different shop" do
    responses.concat([ token_response, verification_response(domain: "other-shop.myshopify.com") ])
    expect_failure("source_mismatch")
  end

  it "requires customer, product and order write permissions" do
    responses.concat([ token_response, verification_response(scopes: %w[read_orders read_products read_customers]) ])
    expect_failure("missing_scopes")
  end

  it "accepts write permissions that include the required read access" do
    responses.concat([ token_response, verification_response(scopes: %w[write_orders write_products write_customers]) ])
    expect(api.verify!).to be(true)
    expect(connection.shopify_granted_scopes).to match_array(%w[write_orders write_products write_customers])
  end

  it "maps Shopify's organization restriction to shop_not_permitted" do
    responses << response(400, error: "Oauth error shop_not_permitted: synthetic organization restriction")
    expect_failure("shop_not_permitted")
  end

  it "maps encrypted credential failures to a safe credential error" do
    allow(connection).to receive(:shopify_access_token).and_raise(ActiveSupport::MessageEncryptor::InvalidMessage)
    expect { api.verify! }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_credentials") }
    allow(connection).to receive(:shopify_access_token).and_call_original
    expect(connection.shopify_access_token).to be_nil
    expect(connection.shopify_refresh_token).to be_nil
    expect(connection.shopify_api_error_code).to eq("invalid_credentials")
    expect(requests).to be_empty
  end

  it "does not expose Shopify error bodies in exceptions" do
    responses << response(401, error: "synthetic-sensitive-response")
    expect { api.verify! }.to raise_error(described_class::Error, "Shopify API: invalid_credentials")
    expect(connection.shopify_api_error_code).to eq("invalid_credentials")
  end

  it "maps forbidden shops, throttling, server failures and malformed responses to safe codes" do
    { 403 => "shop_not_permitted", 429 => "rate_limited", 503 => "unavailable", 302 => "invalid_response" }.each do |status, code|
      connection.shopify_refresh_token = "synthetic-old-refresh"
      connection.shopify_refresh_token_expires_at = 30.days.from_now
      responses << response(status, error: "synthetic")
      expect_failure(code)
    end
  end

  it "maps transport failures to a safe error" do
    responses << Net::ReadTimeout.new("synthetic-private-host")
    expect_failure("unavailable")
  end

  it "preserves authorization through a temporary outage and verifies on retry" do
    connection.shopify_access_token = "cached-token"
    connection.shopify_access_token_expires_at = 5.minutes.from_now
    connection.shopify_api_verified_at = Time.current
    connection.shopify_granted_scopes = described_class::REQUIRED_SCOPES
    access_expiry = connection.shopify_access_token_expires_at
    refresh_expiry = connection.shopify_refresh_token_expires_at
    responses << Net::ReadTimeout.new("synthetic-outage")
    expect_failure("unavailable")
    expect(connection.shopify_access_token).to eq("cached-token")
    expect(connection.shopify_refresh_token).to eq("synthetic-old-refresh")
    expect(connection.shopify_access_token_expires_at).to eq(access_expiry)
    expect(connection.shopify_refresh_token_expires_at).to eq(refresh_expiry)

    responses << verification_response
    expect(api.verify!).to be(true)
    expect(connection.shopify_api_error_code).to be_nil
    expect(connection.shopify_api_verified_at).to be_present
    expect(requests.map { |uri, _request| uri.path }).to all(eq("/admin/api/2026-10/graphql.json"))
  end

  it "retains refresh credentials when token refresh is temporarily unavailable" do
    responses << response(429, error: "synthetic-throttling")
    expect_failure("rate_limited")
    expect(connection.shopify_refresh_token).to eq("synthetic-old-refresh")
    responses.concat([ token_response, verification_response ])
    expect(api.verify!).to be(true)
    expect(connection.shopify_refresh_token).to eq("synthetic-rotated-refresh")
  end

  it "rejects unsafe token lifetimes" do
    responses << response(200, access_token: "synthetic-token", expires_in: 0)
    expect_failure("invalid_response")
  end

  it "rejects a token exchange that omits rotated refresh credentials" do
    responses << response(200, access_token: "synthetic-token", expires_in: 3600)
    expect_failure("invalid_response")
  end

  it "does not persist authorization when the approved shop identity mismatches" do
    responses.concat([ token_response, verification_response(domain: "other-shop.myshopify.com") ])
    expect { api.authorize!(code: "synthetic-code") }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("source_mismatch") }
    expect(connection.shopify_access_token).to be_nil
    expect(connection.shopify_refresh_token).to be_nil
  end

  it "rejects malformed verification data" do
    responses.concat([ token_response, response(200, data: { shop: [] }) ])
    expect_failure("invalid_response")
  end

  it "clears cached authorization when Shopify revokes access" do
    connection.shopify_access_token = "cached-token"
    connection.shopify_access_token_expires_at = 5.minutes.from_now
    connection.shopify_api_verified_at = Time.current
    responses << response(200, errors: [ { extensions: { code: "ACCESS_DENIED" } } ])
    expect_failure("missing_scopes")
  end

  it "rejects oversized response bodies" do
    responses << Struct.new(:code, :body).new("200", "x" * (described_class::MAX_BODY_BYTES + 1))
    expect_failure("invalid_response")
  end

  context "with a persisted merchant connection" do
    let(:store) { Store.create!(name: "Synthetic OAuth merchant", slug: "synthetic-oauth-merchant", storefront_enabled: false) }
    let(:connection) do
      store.store_connections.create!(provider: "shopify", active: true, name: "Synthetic Shopify",
        external_domain: "synthetic-shop.myshopify.com", shopify_oauth: true)
    end

    it "persists encrypted offline credentials and verified permissions after approval" do
      responses.concat([ token_response, verification_response ])
      expect(api.authorize!(code: "synthetic-code")).to be(true)

      connection.reload
      expect(connection.shopify_access_token).to eq("synthetic-token")
      expect(connection.shopify_refresh_token).to eq("synthetic-rotated-refresh")
      expect(connection.shopify_access_token_ciphertext).to be_present
      expect(connection.shopify_access_token_ciphertext).not_to include("synthetic-token")
      expect(connection.shopify_refresh_token_ciphertext).to be_present
      expect(connection.shopify_refresh_token_ciphertext).not_to include("synthetic-rotated-refresh")
      expect(connection.shopify_granted_scopes).to match_array(described_class::REQUIRED_SCOPES)
      expect(connection.shopify_api_connected?).to be(true)
    end

    it "refreshes stored expiring credentials and persists the rotated tokens" do
      responses.concat([ token_response, verification_response ])
      api.authorize!(code: "synthetic-code")
      connection.update!(shopify_access_token_expires_at: 30.seconds.from_now)
      responses.concat([
        response(200, access_token: "synthetic-new-access", expires_in: 3600,
          refresh_token: "synthetic-new-refresh", refresh_token_expires_in: 90.days.to_i),
        verification_response
      ])

      expect(api.verify!).to be(true)
      connection.reload
      expect(connection.shopify_access_token).to eq("synthetic-new-access")
      expect(connection.shopify_refresh_token).to eq("synthetic-new-refresh")
      expect(connection.shopify_api_connected?).to be(true)
      expect(URI.decode_www_form(requests.fetch(2).last.body).to_h).to include(
        "grant_type" => "refresh_token", "refresh_token" => "synthetic-rotated-refresh")
    end
  end
end
