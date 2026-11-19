# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloAllowance do
  let(:store) { Store.create!(slug: "seallo-allowance-#{SecureRandom.hex(5)}", name: "Synthetic quota workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic paid shop", external_domain: "allowance-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_plan_name: "Seallo Basic", shopify_order_limit: 30,
      shopify_entitled_until: 1.day.from_now, shopify_billing_period_start: 10.days.ago, shopify_billing_period_end: 20.days.from_now)
  end

  it "does not enforce a Shopify or Connect order allowance" do
    expect { connection.with_lock { described_class.check!(connection) } }.not_to raise_error
    connection.update!(shopify_entitled_until: nil, shopify_order_limit: 1)
    expect { connection.with_lock { described_class.check!(connection) } }.not_to raise_error
    expect(described_class.used(connection)).to eq(0)
  end

  it "keeps non-Seallo connections outside this helper's duties" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    expect { described_class.check!(legacy) }.not_to raise_error
  end
end
