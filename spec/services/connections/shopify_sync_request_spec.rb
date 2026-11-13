# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::ShopifySyncRequest do
  let(:store) { Store.create!(slug: "sync-request-#{SecureRandom.hex(5)}", name: "Synthetic sync workspace", currency: "MAD") }
  let(:other_store) { Store.create!(slug: "sync-other-#{SecureRandom.hex(5)}", name: "Other synthetic workspace", currency: "MAD") }

  def connection(workspace = store, **attributes)
    workspace.store_connections.create!({ name: "Synthetic Shopify connection", provider: "shopify",
      external_domain: "synthetic-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true,
      shopify_access_token: attributes[:shopify_oauth] == false ? nil : "synthetic-sync-access",
      shopify_access_token_expires_at: 1.hour.from_now,
      shopify_refresh_token_expires_at: 30.days.from_now }.merge(attributes))
  end

  def expect_failure(code)
    expect { yield }.to raise_error(described_class::Error) { |error| expect(error.code).to eq(code) }
    expect(enqueued_jobs).to be_empty
  end

  it "enqueues only the workspace's active OAuth connections with stored credentials" do
    first = connection
    second = connection(shopify_access_token: nil, shopify_refresh_token: "synthetic-sync-refresh")
    connection(other_store)
    connection(active: false)
    connection(shopify_access_token: nil)
    connection(shopify_oauth: false, webhook_secret: "synthetic-legacy-signing-secret")
    connection(provider: "woocommerce", shopify_oauth: false, external_domain: "synthetic.example.test", webhook_secret: "synthetic-woo-signing-secret")

    expect(Connections::ShopifyApi).not_to receive(:new)
    expect(Connections::ShopifyOrderSync).not_to receive(:new)
    expect(described_class.call(store: store)).to eq(2)
    expect(enqueued_jobs.map { |job| job[:job] }).to eq([ ShopifyOrdersSyncJob, ShopifyOrdersSyncJob ])
    expect(enqueued_jobs.map { |job| job[:args] }).to contain_exactly([ first.id ], [ second.id ])
  end

  it "queues only the explicitly selected tenant-owned connection" do
    selected = connection
    connection
    expect(described_class.call(store: store, connection_id: selected.id)).to eq(1)
    expect(enqueued_jobs.map { |job| job[:args] }).to eq([ [ selected.id ] ])
  end

  it "rejects another workspace's connection ID without enqueuing" do
    foreign = connection(other_store)
    expect { described_class.call(store: store, connection_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(enqueued_jobs).to be_empty
  end

  it "rejects an explicit disconnected connection" do
    disconnected = connection(active: false)
    expect_failure("disconnected") { described_class.call(store: store, connection_id: disconnected.id) }
  end

  it "rejects an explicit provider without Shopify OAuth" do
    legacy = connection(shopify_oauth: false, webhook_secret: "synthetic-legacy-signing-secret")
    woo = connection(provider: "woocommerce", shopify_oauth: false, external_domain: "synthetic.example.test", webhook_secret: "synthetic-woo-signing-secret")
    [ legacy, woo ].each do |record|
      expect_failure("credentials_missing") { described_class.call(store: store, connection_id: record.id) }
    end
  end

  it "rejects an explicit connection without stored credentials" do
    pending = connection(shopify_access_token: nil)
    expect_failure("credentials_missing") { described_class.call(store: store, connection_id: pending.id) }
  end

  it "reports when no workspace connections are eligible" do
    connection(active: false)
    connection(shopify_access_token: nil)
    expect_failure("credentials_missing") { described_class.call(store: store) }
  end

  it "allows an unverified connection retaining refresh credentials after a temporary failure" do
    recoverable = connection(shopify_access_token: nil, shopify_refresh_token: "synthetic-retained-refresh",
      shopify_api_verified_at: nil, shopify_api_error_code: "unavailable")
    expect(described_class.call(store: store, connection_id: recoverable.id)).to eq(1)
    expect(enqueued_jobs.map { |job| job[:args] }).to eq([ [ recoverable.id ] ])
  end

  it "rejects a missing workspace safely" do
    expect { described_class.call(store: nil) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(enqueued_jobs).to be_empty
  end

  it "only queues work without changing connection, order, inventory or receipt data" do
    record = connection
    before = [ record.attributes, Order.count, InventoryMovement.count, ExternalOrderReceipt.count ]
    expect(described_class.call(store: store)).to eq(1)
    expect([ record.reload.attributes, Order.count, InventoryMovement.count, ExternalOrderReceipt.count ]).to eq(before)
  end
end
