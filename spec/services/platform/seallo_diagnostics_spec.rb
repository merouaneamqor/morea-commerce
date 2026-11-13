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
  let(:payload) do
    { "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => nil }
  end
  subject(:diagnostics) { described_class.new(actor: actor) }

  before do
    # No test may fall through to a live signed bridge operation.
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise("Unexpected bridge request")
    allow(Connections::SealloBridge).to receive(:graphql).and_raise("Unexpected GraphQL request")
  end

  it "requires an active persisted superadmin for either operation" do
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!", admin: true)
    [ nil, merchant, User.new(super_admin: true), actor.tap { |user| user.update!(status: "suspended") } ].each do |user|
      service = described_class.new(actor: user)
      expect { service.recheck(connection: connection) }.to raise_error(ActiveRecord::RecordNotFound)
      expect { service.diagnose_link(authorization: authorization) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "keeps disconnected records inactive without contacting providers" do
    connection.update!(active: false)
    expect(Connections::SealloEntitlement).not_to receive(:refresh!)
    expect(Connections::ShopifyApi).not_to receive(:new)
    result = diagnostics.recheck(connection: connection)
    expect(result.code).to eq("disconnected")
    expect(result).not_to be_success
    expect(connection.reload).not_to be_active
  end

  it "rejects a demoted superadmin even when the caller holds a stale user" do
    actor.update!(store: store)
    User.find(actor.id).update!(super_admin: false)
    expect { diagnostics.recheck(connection: connection) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { diagnostics.diagnose_link(authorization: authorization) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "rejects non-Seallo connections without provider calls" do
    connection.update!(shopify_app: nil)
    expect(Connections::SealloEntitlement).not_to receive(:refresh!)
    expect(diagnostics.recheck(connection: connection).code).to eq("unsupported_connection")
  end

  it "refreshes the current plan then verifies Shopify without importing orders" do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: connection.external_domain).and_return(payload)
    api = instance_double(Connections::ShopifyApi)
    expect(Connections::ShopifyApi).to receive(:new).with(connection: connection).and_return(api)
    expect(api).to receive(:verify!) do
      expect(connection.reload.shopify_order_limit).to eq(30)
      true
    end
    result = nil
    expect { result = diagnostics.recheck(connection: connection) }.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(result).to be_success
    expect(result.to_h).to eq(code: "verified", plan_name: "Seallo Basic", order_limit: 30, period_end: nil)
    expect(connection.reload.shopify_entitled_until).to be_future
  end

  it "does not verify Shopify when no plan is active" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_return("active" => false)
    expect(Connections::ShopifyApi).not_to receive(:new)
    expect(diagnostics.recheck(connection: connection).code).to eq("not_entitled")
  end

  it "returns a safe actionable Shopify permission error" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(payload)
    api = instance_double(Connections::ShopifyApi)
    allow(Connections::ShopifyApi).to receive(:new).and_return(api)
    allow(api).to receive(:verify!).and_raise(Connections::ShopifyApi::Error.new("missing_scopes"))
    result = diagnostics.recheck(connection: connection)
    expect(result.code).to eq("missing_scopes")
    expect(result.message).to include("protected customer data")
    expect(result.plan_name).to be_nil
  end

  it "maps unknown bridge error text to a fixed safe message" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise(Connections::SealloBridge::Error, "private upstream payload synthetic-secret")
    result = diagnostics.recheck(connection: connection)
    expect(result.code).to eq("invalid_response")
    expect(result.to_h.to_s + result.message).not_to include("synthetic-secret", "private upstream")
  end

  it "diagnoses an initial link using the shared plan contract without writing or consuming it" do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: authorization.shop_domain).and_return(payload)
    original = authorization.attributes
    expect(Connections::ShopifyApi).not_to receive(:new)
    expect(Connections::SealloEntitlement).not_to receive(:refresh!)
    result = nil
    expect { result = diagnostics.diagnose_link(authorization: authorization) }.not_to change(StoreConnection, :count)
    expect(result.to_h).to eq(code: "entitlement_verified", plan_name: "Seallo Basic", order_limit: 30, period_end: nil)
    expect(result).to be_success
    expect(authorization.reload.attributes).to eq(original)
    expect(result.to_h.to_s).not_to include(authorization.digest)
  end

  it "accepts current Pro and Premium plans with explicit absent period ends" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(payload)
    { "Seallo Pro" => 100, "Seallo Premium" => nil }.each do |name, limit|
      payload.merge!("plan_name" => name, "order_limit" => limit)
      expect(diagnostics.diagnose_link(authorization: authorization)).to have_attributes(code: "entitlement_verified", plan_name: name, order_limit: limit)
    end
  end

  it "rejects unknown plans, old quotas, missing fields and invalid periods on initial links" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(payload)
    original = payload.dup
    [ original.merge("plan_name" => "Unknown"), original.merge("order_limit" => 19), original.except("current_period_end"),
      original.merge("current_period_start" => 1.minute.from_now.iso8601), original.merge("current_period_end" => 1.minute.ago.iso8601) ].each do |invalid|
      payload.replace(invalid)
      expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("invalid_response")
      expect(authorization.reload.consumed_at).to be_nil
    end
  end

  it "returns inactive billing without granting a connection" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_return("active" => false)
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("not_entitled")
    expect(authorization.reload.consumed_at).to be_nil
  end

  it "rejects expired, consumed and unrecognized pending identities without provider calls" do
    authorization.update!(expires_at: 1.second.ago)
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("authorization_expired")
    authorization.update!(expires_at: 10.minutes.from_now, consumed_at: Time.current)
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("authorization_consumed")
    authorization.update!(consumed_at: nil, shop_domain: "https://untrusted.example.test")
    expect(diagnostics.diagnose_link(authorization: authorization).code).to eq("source_mismatch")
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "requires a stored authorization rather than a submitted domain" do
    expect { diagnostics.diagnose_link(authorization: SealloConnectionCode.new(shop_domain: "other.myshopify.com")) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end
end
