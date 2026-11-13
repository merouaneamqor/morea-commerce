# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Shopify uninstall lifecycle", type: :request do
  let(:secret) { "synthetic-shopify-lifecycle-secret" }
  let(:shop) { "synthetic-uninstall.myshopify.com" }
  let(:store) { Store.create!(slug: "uninstall-#{SecureRandom.hex(5)}", name: "Synthetic lifecycle workspace", currency: "MAD") }
  let!(:connection) do
    store.store_connections.create!(name: "Synthetic Shopify", provider: "shopify", external_domain: shop, shopify_oauth: true,
      shopify_access_token: "synthetic-access", shopify_refresh_token: "synthetic-refresh",
      shopify_access_token_expires_at: 1.hour.from_now, shopify_refresh_token_expires_at: 30.days.from_now,
      shopify_api_verified_at: 1.hour.ago, shopify_granted_scopes: [ "read_orders" ],
      shopify_oauth_state_digest: SecureRandom.hex(32), shopify_oauth_state_expires_at: 5.minutes.from_now,
      shopify_webhook_checked_at: Time.current)
  end
  let(:body) { { myshopify_domain: shop }.to_json }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(secret)
    host! Store.base_domain
  end

  def deliver(payload = body, changes = {})
    headers = { "CONTENT_TYPE" => "application/json", "X-Shopify-Topic" => "app/uninstalled",
      "X-Shopify-Shop-Domain" => shop, "X-Shopify-Triggered-At" => Time.current.iso8601,
      "X-Shopify-Hmac-SHA256" => Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, payload)) }
    post "/webhooks/shopify/uninstalled", params: payload, headers: headers.merge(changes)
  end

  it "clears API credentials and pending authorization without deleting the connection on repeated deliveries" do
    receipt = connection.external_order_receipts.create!(external_id: "synthetic-rejected-order", status: "rejected", error_code: "invalid_order", received_at: Time.current)
    2.times do
      expect { deliver }.not_to change(StoreConnection, :count)
      expect(response).to have_http_status(:ok)
    end
    connection.reload
    expect(connection).not_to be_active
    %i[shopify_access_token_ciphertext shopify_refresh_token_ciphertext shopify_access_token_expires_at
      shopify_refresh_token_expires_at shopify_api_verified_at shopify_oauth_state_digest
      shopify_oauth_state_expires_at shopify_webhook_checked_at].each do |field|
      expect(connection.public_send(field)).to be_nil
    end
    expect(connection.shopify_granted_scopes).to be_empty
    expect(receipt.reload.store_connection_id).to eq(connection.id)
  end

  it "preserves another shop and legacy webhook credentials" do
    other = store.store_connections.create!(name: "Other shop", provider: "shopify", external_domain: "other-uninstall.myshopify.com", shopify_oauth: true)
    legacy_store = Store.create!(slug: "legacy-#{SecureRandom.hex(5)}", name: "Legacy synthetic workspace", currency: "MAD")
    legacy = legacy_store.store_connections.create!(name: "Legacy Shopify", provider: "shopify", external_domain: shop, webhook_secret: "synthetic-legacy-secret")
    deliver
    expect(response).to have_http_status(:ok)
    expect(other.reload).to be_active
    expect(legacy.reload).to be_active
    expect(legacy.webhook_secret).to eq("synthetic-legacy-secret")
  end

  it "rejects signatures, origins and topics before changing credentials" do
    [ { "X-Shopify-Hmac-SHA256" => "invalid" }, { "X-Shopify-Shop-Domain" => "foreign.myshopify.com" },
      { "X-Shopify-Topic" => "orders/create" } ].each do |headers|
      deliver(body, headers)
      expect(response.status).to be_between(400, 499)
      expect(connection.reload).to be_active
      expect(connection.shopify_access_token).to eq("synthetic-access")
    end
  end

  it "rejects invalid payloads and oversized deliveries" do
    [ "{", "[]", { myshopify_domain: "bad.example.test" }.to_json, "x" * 65_537 ].each do |payload|
      deliver(payload)
      expect(response.status).to be_between(400, 499)
    end
    expect(connection.reload).to be_active
  end

  it "acknowledges unknown shops without revealing tenant records" do
    unknown = "unknown-uninstall.myshopify.com"
    deliver({ myshopify_domain: unknown }.to_json, "X-Shopify-Shop-Domain" => unknown)
    expect(response).to have_http_status(:ok)
    expect(connection.reload).to be_active
  end

  it "does not trust an unsigned event timestamp to retain credentials" do
    deliver(body, "X-Shopify-Triggered-At" => 2.hours.ago.iso8601)
    expect(response).to have_http_status(:ok)
    expect(connection.reload).not_to be_active
    expect(connection.shopify_access_token).to be_nil
  end

  it "fails safely when app credentials are missing" do
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(nil)
    deliver
    expect(response).to have_http_status(:service_unavailable)
    expect(connection.reload).to be_active
  end
end
