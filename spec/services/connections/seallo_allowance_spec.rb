# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloAllowance do
  let(:store) { Store.create!(slug: "seallo-allowance-#{SecureRandom.hex(5)}", name: "Synthetic quota workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic paid shop", external_domain: "allowance-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_plan_name: "Basic", shopify_order_limit: 30,
      shopify_entitled_until: 1.day.from_now, shopify_billing_period_start: 10.days.ago, shopify_billing_period_end: 20.days.from_now)
  end
  let(:customer) { store.customers.create!(name: "Synthetic quota customer", phone: "+212600000099", city: "Synthetic City") }

  def accepted_receipt(received_at: Time.current, connection: self.connection)
    order = connection.store.orders.create!(customer: customer, status: "new", customer_name: customer.name,
      customer_phone: customer.phone, customer_city: "Synthetic City", customer_address: "Synthetic Street", total_cents: 10000)
    connection.external_order_receipts.create!(external_id: "synthetic-#{SecureRandom.hex(8)}", order: order, status: "accepted", received_at: received_at)
  end

  def expect_failure(code, status)
    expect { connection.with_lock { described_class.check!(connection) } }
      .to raise_error(Connections::WebhookIntake::Error) { |error| expect([ error.message, error.status ]).to eq([ code, status ]) }
  end

  it "allows the 30th Basic import, then blocks the 31st without creating a receipt" do
    29.times { accepted_receipt }
    expect(described_class.used(connection)).to eq(29)
    expect { connection.with_lock { described_class.check!(connection) } }.not_to raise_error
    accepted_receipt
    expect(described_class.used(connection)).to eq(30)
    expect_failure("order_limit_reached", 429)
    expect(connection.external_order_receipts.count).to eq(30)
  end

  it "allows the 100th Pro import and blocks the next one" do
    connection.update!(shopify_plan_name: "Pro", shopify_order_limit: 100)
    99.times { accepted_receipt }
    expect { connection.with_lock { described_class.check!(connection) } }.not_to raise_error
    accepted_receipt
    expect_failure("order_limit_reached", 429)
    expect(described_class.used(connection)).to eq(100)
  end

  it "permits unlimited imports only while Premium has a current entitlement" do
    connection.update!(shopify_plan_name: "Premium", shopify_order_limit: nil)
    allow(described_class).to receive(:used).and_raise("Unlimited plans must not count receipts")
    expect { connection.with_lock { described_class.check!(connection) } }.not_to raise_error
    connection.update!(shopify_entitled_until: 1.second.ago)
    expect_failure("subscription_required", 402)
  end

  it "fails closed for an absent entitlement even when the limit is unlimited" do
    connection.update!(shopify_entitled_until: nil, shopify_order_limit: nil)
    expect_failure("subscription_required", 402)
  end

  it "rejects expired entitlements and billing periods outside the current time" do
    freeze_time do
      original = connection.attributes.slice("shopify_entitled_until", "shopify_billing_period_start", "shopify_billing_period_end")
      [ { shopify_entitled_until: Time.current },
        { shopify_billing_period_start: 1.second.from_now },
        { shopify_billing_period_end: Time.current } ].each do |attributes|
        connection.update!(attributes)
        expect_failure("subscription_required", 402)
        connection.update!(original)
      end
    end
  end

  it "counts only accepted receipts inside the current period, with an exclusive end" do
    freeze_time do
      accepted_receipt(received_at: connection.shopify_billing_period_start - 1.second)
      accepted_receipt(received_at: connection.shopify_billing_period_start)
      accepted_receipt(received_at: connection.shopify_billing_period_end - 1.second)
      accepted_receipt(received_at: connection.shopify_billing_period_end)
      connection.external_order_receipts.create!(external_id: "rejected-synthetic", status: "rejected", error_code: "not_cod", received_at: Time.current)
      expect(described_class.used(connection)).to eq(2)
    end
  end

  it "does not count receipts from another connected shop" do
    other = store.store_connections.create!(provider: "shopify", name: "Other synthetic shop", external_domain: "other-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
    accepted_receipt(connection: other)
    expect(described_class.used(connection)).to eq(0)
  end

  it "keeps the same receipt from consuming allowance again on delivery replay" do
    receipt = accepted_receipt
    expect(described_class.used(connection)).to eq(1)
    connection.update!(shopify_entitled_until: 1.second.ago)
    expect(described_class).not_to receive(:check!)
    result = Connections::WebhookIntake.new(connection: connection).import("id" => receipt.external_id)
    expect(result.replayed).to be(true)
    expect(result.receipt.id).to eq(receipt.id)
    expect(described_class.used(connection)).to eq(1)
  end

  it "stops intake at the limit before normalization and leaves no rejection receipt to block a retry" do
    connection.update!(shopify_order_limit: 1)
    accepted_receipt
    expect(Connections::OrderNormalizer).not_to receive(:new)
    expect { Connections::WebhookIntake.new(connection: connection).import("id" => "blocked-synthetic-order") }
      .to raise_error(Connections::WebhookIntake::Error) { |error| expect([ error.message, error.status ]).to eq([ "order_limit_reached", 429 ]) }
    expect(connection.external_order_receipts.find_by(external_id: "blocked-synthetic-order")).to be_nil
    expect(connection.external_order_receipts.count).to eq(1)
    expect(store.orders.count).to eq(1)
  end

  it "does not apply Seallo plans to the existing Shopify app or other providers" do
    [ [ "shopify", true, nil ], [ "woocommerce", false, "synthetic-legacy-webhook-secret" ] ].each do |provider, oauth, secret|
      legacy = store.store_connections.create!(provider: provider, shopify_oauth: oauth, name: "Legacy #{provider}",
        external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", webhook_secret: secret)
      expect { described_class.check!(legacy) }.not_to raise_error
      expect(described_class.used(legacy)).to eq(0)
    end
  end
end
