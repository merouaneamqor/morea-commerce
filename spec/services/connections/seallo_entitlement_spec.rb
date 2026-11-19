# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloEntitlement do
  let(:store) { Store.create!(slug: "seallo-entitlement-#{SecureRandom.hex(5)}", name: "Synthetic entitlement workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic billed shop", external_domain: "entitlement-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end
  let(:shopify_payload) do
    { "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601 }
  end

  before do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: connection.external_domain).and_return(shopify_payload)
  end

  def require_seallo_billing!
    store.update!(subscription_required: true, billing_status: "canceled", billing_period_ends_on: 1.day.ago, trial_ends_at: nil, plan: nil)
  end

  it "uses the Seallo workspace plan and config/plans.yml order limits without calling Shopify" do
    freeze_time do
      store.update!(subscription_required: true, plan: "starter", billing_status: "active",
        billing_interval: "monthly", billing_period_ends_on: Date.current + 20.days, trial_ends_at: nil)
      expect(Connections::SealloBridge).not_to receive(:entitlement)
      expect(described_class.refresh!(connection)).to be(true)
      expect(connection.reload).to have_attributes(shopify_plan_name: "Starter", shopify_order_limit: 300,
        shopify_entitled_until: 15.minutes.from_now)
    end
  end

  it "maps every Seallo plan order allowance from Plans configuration" do
    freeze_time do
      Plans.list.each do |key, config|
        store.update!(subscription_required: !Plans.free?(key), plan: key, billing_status: "active",
          billing_interval: "monthly", billing_period_ends_on: Date.current + 10.days, trial_ends_at: nil)
        expect(described_class.refresh!(connection)).to be(true)
        expect(connection.reload).to have_attributes(shopify_plan_name: config.fetch("name"), shopify_order_limit: config["orders"])
      end
      expect(Connections::SealloBridge).not_to have_received(:entitlement)
    end
  end

  it "falls back to a still-active Shopify legacy contract when Seallo billing is inactive" do
    freeze_time do
      require_seallo_billing!
      described_class::SHOPIFY_LEGACY_PLANS.each do |name, limit|
        shopify_payload.merge!("plan_name" => name, "order_limit" => limit)
        expect(described_class.refresh!(connection)).to be(true)
        expect(connection.reload).to have_attributes(shopify_plan_name: name, shopify_order_limit: limit,
          shopify_entitled_until: 15.minutes.from_now)
      end
    end
  end

  it "accepts an ACTIVE Shopify-legacy trial without a cycle end only for the short cache lifetime" do
    freeze_time do
      require_seallo_billing!
      shopify_payload["current_period_end"] = nil
      shopify_payload.merge!("plan_name" => "Seallo Pro", "order_limit" => 100)
      expect(described_class.refresh!(connection)).to be(true)
      expect(connection.reload.shopify_billing_period_end).to be_nil
      expect(connection.shopify_entitled_until).to eq(15.minutes.from_now)
      expect { Connections::SealloAllowance.check!(connection) }.not_to raise_error
      travel 15.minutes
      expect { Connections::SealloAllowance.check!(connection) }.to raise_error(Connections::WebhookIntake::Error)
    end
  end

  it "rejects the retired 19 and 99 order limits instead of accepting a mismatched Shopify contract" do
    require_seallo_billing!
    [ [ "Seallo Basic", 19 ], [ "Seallo Pro", 99 ] ].each do |name, limit|
      shopify_payload.merge!("plan_name" => name, "order_limit" => limit)
      expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "invalid_response")
      expect(connection.reload.shopify_entitled_until).to be_nil
    end
  end

  it "caps the Seallo cache at the end of a near-expiry billing period" do
    freeze_time do
      store.update!(subscription_required: true, plan: "intermediate", billing_status: "active",
        billing_interval: "monthly", billing_period_ends_on: Date.current, trial_ends_at: nil)
      described_class.refresh!(connection)
      expect(connection.reload.shopify_entitled_until).to eq(Date.current.in_time_zone.end_of_day)
    end
  end

  it "clears entitlement when neither Seallo billing nor Shopify legacy is active" do
    require_seallo_billing!
    described_class.refresh!(connection)
    shopify_payload["active"] = false
    expect(described_class.refresh!(connection)).to be(false)
    expect(connection.reload.shopify_entitled_until).to be_nil
  end

  it "requires an explicit active boolean on the Shopify-legacy payload" do
    require_seallo_billing!
    shopify_payload["active"] = "true"
    expect(described_class.refresh!(connection)).to be(false)
    expect(connection.reload.shopify_entitled_until).to be_nil
  end

  it "rejects unknown Shopify-legacy plans and mismatched quotas without granting access" do
    require_seallo_billing!
    [ { "plan_name" => "Synthetic unknown", "order_limit" => nil },
      { "plan_name" => "Seallo Basic", "order_limit" => nil },
      { "plan_name" => "Seallo Pro", "order_limit" => 30 },
      { "plan_name" => "Seallo Premium", "order_limit" => 100 } ].each do |attributes|
      shopify_payload.merge!(attributes)
      expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "invalid_response")
      expect(connection.reload.shopify_entitled_until).to be_nil
    end
  end

  it "keeps the old standalone Shopify app out of Seallo billing" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy app", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    expect(Connections::SealloBridge).not_to receive(:entitlement)
    expect(described_class.refresh!(legacy)).to be_nil
  end

  it "propagates temporary Shopify-fallback bridge failures without inventing an entitlement" do
    require_seallo_billing!
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise(Connections::SealloBridge::Error, "unavailable")
    expect { described_class.refresh!(connection) }.to raise_error(Connections::SealloBridge::Error, "unavailable")
    expect(connection.reload.shopify_entitled_until).to be_nil
  end

  it "presents an inactive payload for an unlinked or expired cache without calling Shopify" do
    expect(described_class.inactive_payload).to include("active" => false, "plan_name" => nil, "order_limit" => nil)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end
end
