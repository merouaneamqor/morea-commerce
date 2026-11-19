# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::SealloDiagnostics do
  let(:actor) { User.create!(email: "support-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!", super_admin: true, admin: true) }
  let(:store) { Store.create!(slug: "diagnostics-#{SecureRandom.hex(5)}", name: "Synthetic diagnostic workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic Seallo shop", external_domain: "support-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end
  let(:authorization) do
    SealloConnectionCode.create!(store: store, user: actor, digest: SecureRandom.hex(32),
      shop_domain: "pending-#{SecureRandom.hex(5)}.myshopify.com", expires_at: 10.minutes.from_now)
  end
  subject(:diagnostics) { described_class.new(actor: actor) }

  before do
    allow(Connections::SealloBridge).to receive(:request).and_raise("Unexpected bridge request")
    allow(Connections::SealloBridge).to receive(:graphql).and_raise("Unexpected GraphQL request")
  end

  it "requires an active persisted superadmin for either operation" do
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!", admin: true)
    [ nil, merchant, User.new(super_admin: true), actor.tap { |user| user.update!(status: "suspended") } ].each do |user|
      service = described_class.new(actor: user)
      expect { service.recheck(connection: connection) }.to raise_error(ActiveRecord::RecordNotFound)
      expect { service.diagnose_link(authorization: authorization) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "keeps disconnected records inactive without contacting providers" do
    connection.update!(active: false)
    expect(Connections::ShopifyApi).not_to receive(:new)
    result = diagnostics.recheck(connection: connection)
    expect(result.code).to eq("disconnected")
    expect(result).not_to be_success
  end

  it "rejects non-Seallo connections without provider calls" do
    connection.update!(shopify_app: nil)
    expect(diagnostics.recheck(connection: connection).code).to eq("unsupported_connection")
  end

  it "verifies Shopify access without a Shopify plan refresh" do
    api = instance_double(Connections::ShopifyApi)
    expect(Connections::ShopifyApi).to receive(:new).with(connection: connection).and_return(api)
    expect(api).to receive(:verify!)
    expect(Connections::SealloBridge).not_to receive(:request)
    result = diagnostics.recheck(connection: connection)
    expect(result).to be_success
    expect(result.code).to eq("verified")
  end

  it "returns a safe actionable Shopify permission error" do
    api = instance_double(Connections::ShopifyApi)
    allow(Connections::ShopifyApi).to receive(:new).and_return(api)
    allow(api).to receive(:verify!).and_raise(Connections::ShopifyApi::Error.new("missing_scopes"))
    result = diagnostics.recheck(connection: connection)
    expect(result.code).to eq("missing_scopes")
    expect(result.message).to include("protected customer data")
  end

  it "diagnoses a pending link without Shopify billing" do
    original = authorization.attributes
    expect(Connections::ShopifyApi).not_to receive(:new)
    expect(Connections::SealloBridge).not_to receive(:request)
    result = nil
    expect { result = diagnostics.diagnose_link(authorization: authorization) }.not_to change(StoreConnection, :count)
    expect(result.to_h).to eq(code: "link_ready", plan_name: nil, order_limit: nil, period_end: nil)
    expect(result).to be_success
    expect(authorization.reload.attributes).to eq(original)
  end

  it "rejects expired, consumed and unrecognized pending identities without provider calls" do
    authorization.update!(expires_at: 1.second.ago)
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("authorization_expired")
    authorization.update!(expires_at: 10.minutes.from_now, consumed_at: Time.current)
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("authorization_consumed")
    authorization.update!(consumed_at: nil, shop_domain: "https://untrusted.example.test")
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("source_mismatch")
  end

  it "requires a stored authorization rather than a submitted domain" do
    expect { diagnostics.diagnose_link(authorization: SealloConnectionCode.new(shop_domain: "other.myshopify.com")) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
