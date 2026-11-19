# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloEntitlement do
  let(:store) { Store.create!(slug: "seallo-entitlement-#{SecureRandom.hex(5)}", name: "Synthetic entitlement workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic billed shop", external_domain: "entitlement-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end

  it "treats Seallo Connect as free and does not call Shopify billing" do
    expect(Connections::SealloBridge).not_to receive(:request)
    expect(described_class.refresh!(connection)).to be(true)
  end

  it "keeps the old standalone Shopify app out of Seallo Connect billing helpers" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy app", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    expect(Connections::SealloBridge).not_to receive(:request)
    expect(described_class.refresh!(legacy)).to be_nil
  end
end
