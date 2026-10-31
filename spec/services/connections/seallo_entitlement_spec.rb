# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloEntitlement do
  let(:store) { Store.create!(slug: "seallo-entitlement-#{SecureRandom.hex(5)}", name: "Synthetic entitlement workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic billed shop", external_domain: "entitlement-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end
  let(:payload) do
    { "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601 }
  end

  before do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: connection.external_domain).and_return(payload)
  end

  it "caches each recognized plan with its verified allowance for at most 15 minutes" do
    freeze_time do
      described_class::PLANS.each do |name, limit|
        payload.merge!("plan_name" => name, "order_limit" => limit)
        expect(described_class.refresh!(connection)).to be(true)
        expect(connection.reload).to have_attributes(shopify_plan_name: name, shopify_order_limit: limit,
          shopify_entitled_until: 15.minutes.from_now)
        expect(connection.shopify_billing_period_start).to eq(Time.iso8601(payload["current_period_start"]))
        expect(connection.shopify_billing_period_end).to eq(Time.iso8601(payload["current_period_end"]))
      end
    end
  end

  it "caps the cache at the end of a near-expiry billing period" do
    freeze_time do
      payload["current_period_end"] = 2.minutes.from_now.iso8601
      described_class.refresh!(connection)
      expect(connection.reload.shopify_entitled_until).to eq(2.minutes.from_now)
    end
  end

  it "clears entitlement immediately for an inactive subscription" do
    described_class.refresh!(connection)
    payload["active"] = false
    expect(described_class.refresh!(connection)).to be(false)
    expect(connection.reload.shopify_entitled_until).to be_nil
  end

  it "requires an explicit active boolean rather than a truthy string" do
    payload["active"] = "true"
    expect(described_class.refresh!(connection)).to be(false)
    expect(connection.reload.shopify_entitled_until).to be_nil
  end

  it "rejects unknown plans and mismatched or missing quotas without granting access" do
    [ { "plan_name" => "Synthetic unknown", "order_limit" => nil },
      { "plan_name" => "Seallo Basic", "order_limit" => nil },
      { "plan_name" => "Seallo Pro", "order_limit" => 30 },
      { "plan_name" => "Seallo Premium", "order_limit" => 100 } ].each do |attributes|
      payload.merge!(attributes)
      expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "invalid_response")
      expect(connection.reload.shopify_entitled_until).to be_nil
    end
  end

  it "rejects expired, future-starting and malformed billing periods" do
    original = payload.dup
    [ { "current_period_end" => 1.second.ago.iso8601 },
      { "current_period_start" => 1.minute.from_now.iso8601 },
      { "current_period_start" => "invalid" },
      { "current_period_end" => nil } ].each do |attributes|
      payload.replace(original.merge(attributes))
      expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "invalid_response")
      expect(connection.reload.shopify_entitled_until).to be_nil
    end
  end

  it "keeps the old standalone Shopify app out of Seallo billing" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy app", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    expect(Connections::SealloBridge).not_to receive(:entitlement)
    expect(described_class.refresh!(legacy)).to be_nil
  end

  it "propagates temporary bridge failures without inventing an entitlement" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise(Connections::SealloBridge::Error, "unavailable")
    expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "unavailable")
    expect(connection.reload.shopify_entitled_until).to be_nil
  end
end
