# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloEntitlement do
  let(:store) { Store.create!(slug: "seallo-entitlement-#{SecureRandom.hex(5)}", name: "Synthetic entitlement workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic billed shop", external_domain: "entitlement-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end

  it "treats Seallo Connect as free and does not call Shopify billing" do
    expect(Connections::SealloBridge).not_to receive(:entitlement)
    expect(described_class.refresh!(connection)).to be(true)
  end

  it "keeps the old standalone Shopify app out of Seallo Connect billing helpers" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy app", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    expect(Connections::SealloBridge).not_to receive(:entitlement)
    expect(described_class.refresh!(legacy)).to be_nil
  end

  it "still parses historical Partner payloads for diagnostics without granting new access paths" do
    payload = { "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601 }
    expect(described_class.attributes_for(payload)).to include(shopify_plan_name: "Seallo Basic", shopify_order_limit: 30)
    expect(described_class.attributes_for(payload.merge("active" => false))).to be_nil
  end
end
