# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloWebhooks do
  let(:secret) { "synthetic-seallo-shopify-secret" }
  let(:bridge_secret) { "synthetic-seallo-bridge-secret" }
  let(:store) { Store.create!(slug: "privacy-#{SecureRandom.hex(5)}", name: "Synthetic privacy workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) { store.store_connections.create!(provider: "shopify", name: "Seallo", external_domain: "privacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true, shopify_app: "seallo_connect") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SEALLO_SHOPIFY_CLIENT_SECRET").and_return(secret)
    allow(ENV).to receive(:[]).with("SEALLO_BRIDGE_SECRET").and_return(bridge_secret)
  end

  def delivery(topic, payload, shop: connection.external_domain, signature: nil, webhook_id: "synthetic-delivery-id")
    body = JSON.generate(payload)
    headers = { "X-Shopify-Topic" => topic, "X-Shopify-Shop-Domain" => shop,
      "X-Shopify-Hmac-SHA256" => signature || Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body)),
      "X-Shopify-Webhook-Id" => webhook_id, "X-Seallo-Timestamp" => Time.current.to_i.to_s }
    message = [ headers["X-Seallo-Timestamp"], shop, topic, webhook_id, body ].join("\n")
    headers["X-Seallo-Webhook-Signature"] = OpenSSL::HMAC.hexdigest("sha256", bridge_secret, message)
    described_class.call(body: body, headers: headers)
  end

  it "rejects invalid signatures even for unknown shops" do
    expect { delivery("shop/redact", { shop_domain: "unknown.myshopify.com" }, shop: "unknown.myshopify.com", signature: "forged") }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(401) }
    expect(ShopifyPrivacyRequest.count).to eq(0)
  end

  it "requires the signed payload's shop to match the delivery domain" do
    expect { delivery("shop/redact", { shop_domain: "foreign.myshopify.com" }) }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(403) }
  end

  it "rejects missing relay signatures and timestamp or topic tampering" do
    body = JSON.generate(shop_domain: connection.external_domain)
    expect { described_class.call(body: body, headers: {}) }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(401) }
    timestamp = 301.seconds.ago.to_i.to_s
    headers = { "X-Seallo-Timestamp" => timestamp, "X-Shopify-Webhook-Id" => "synthetic-delivery-id",
      "X-Shopify-Shop-Domain" => connection.external_domain, "X-Shopify-Topic" => "shop/redact" }
    message = [ timestamp, connection.external_domain, "customers/data_request", "synthetic-delivery-id", body ].join("\n")
    headers["X-Seallo-Webhook-Signature"] = OpenSSL::HMAC.hexdigest("sha256", bridge_secret, message)
    expect { described_class.call(body: body, headers: headers) }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(401) }
    headers["X-Seallo-Timestamp"] = Time.current.to_i.to_s
    message = [ headers["X-Seallo-Timestamp"], connection.external_domain, "customers/data_request", "synthetic-delivery-id", body ].join("\n")
    headers["X-Seallo-Webhook-Signature"] = OpenSSL::HMAC.hexdigest("sha256", bridge_secret, message)
    expect { described_class.call(body: body, headers: headers) }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(401) }
  end

  it "keeps separate privacy events with identical bodies separate" do
    payload = { shop_domain: connection.external_domain }
    delivery("shop/redact", payload, webhook_id: "first-event")
    delivery("shop/redact", payload, webhook_id: "second-event")
    expect(ShopifyPrivacyRequest.count).to eq(2)
  end

  it "durably accepts unknown-shop privacy requests and completes without querying another connection" do
    delivery("shop/redact", { shop_domain: "unknown.myshopify.com" }, shop: "unknown.myshopify.com")
    record = ShopifyPrivacyRequest.last
    expect(record.store_connection).to be_nil
    record.process!
    expect(record.reload.status).to eq("completed")
    expect(record.identifiers_ciphertext).to be_nil
  end

  it "deduplicates privacy deliveries and encrypts only the required identifiers" do
    payload = { shop_domain: connection.external_domain, customer: { id: 123, email: "synthetic@example.test" },
      orders_requested: [ 456 ], data_request: { id: 789 } }
    2.times { delivery("customers/data_request", payload) }
    expect(ShopifyPrivacyRequest.count).to eq(1)
    record = ShopifyPrivacyRequest.last
    expect(record.identifiers["order_ids"]).to eq([ "456" ])
    expect(record.identifiers_ciphertext).not_to include("456", "synthetic@example.test")
    expect(record.identifiers).not_to have_key("email")
    expect(enqueued_jobs.count { |job| job[:job] == ShopifyPrivacyRequestJob }).to eq(2)
  end

  it "uninstalls only the Seallo connection and clears credentials on repeated delivery" do
    connection.update!(shopify_access_token: "synthetic-access", shopify_access_token_expires_at: 1.hour.from_now,
      shopify_refresh_token: "synthetic-refresh", shopify_refresh_token_expires_at: 30.days.from_now,
      shopify_api_verified_at: Time.current)
    foreign = store.store_connections.create!(provider: "shopify", name: "Legacy", external_domain: "legacy.myshopify.com", shopify_oauth: true)
    2.times { delivery("app/uninstalled", { myshopify_domain: connection.external_domain }) }
    expect(connection.reload.active?).to be(false)
    expect(connection.shopify_access_token_ciphertext).to be_nil
    expect(connection.shopify_refresh_token_ciphertext).to be_nil
    expect(foreign.reload.active?).to be(true)
  end

  it "passes signed eligible order deliveries to the existing receipt-backed intake" do
    intake = instance_double(Connections::WebhookIntake)
    receipt = instance_double(ExternalOrderReceipt, status: "accepted", error_code: nil)
    allow(Connections::WebhookIntake).to receive(:new).with(connection: connection).and_return(intake)
    expect(intake).to receive(:call).with(body: JSON.generate(id: 42), headers: hash_including("X-Shopify-Topic" => "orders/create"))
      .and_return(Connections::WebhookIntake::Result.new(receipt: receipt, replayed: true))
    expect(delivery("orders/create", { id: 42 })).to include(status: "accepted", replayed: true)
  end

  it "does not let a retried uninstall revoke a replacement installation" do
    payload = { myshopify_domain: connection.external_domain }
    delivery("app/uninstalled", payload, webhook_id: "old-uninstall")
    connection.reload.update!(active: true, shopify_access_token: "synthetic-new-installation-token",
      shopify_access_token_expires_at: 1.hour.from_now)
    delivery("app/uninstalled", payload, webhook_id: "old-uninstall")
    expect(connection.reload.active?).to be(true)
    expect(connection.shopify_access_token).to eq("synthetic-new-installation-token")
    delivery("app/uninstalled", payload, webhook_id: "new-uninstall")
    expect(connection.reload.active?).to be(false)
    expect(connection.shopify_access_token_ciphertext).to be_nil
  end
end
