# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::WebhookIntake do
  let(:secret) { "synthetic-webhook-subscription-secret" }
  let(:store) do
    Store.create!(slug: "hook-subscription-#{SecureRandom.hex(5)}", name: "Synthetic webhook workspace",
      currency: "MAD", storefront_enabled: false, subscription_required: true, billing_status: "canceled")
  end
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic Shopify",
      external_domain: "synthetic-#{SecureRandom.hex(5)}.myshopify.com", webhook_secret: secret)
  end
  let(:body) do
    JSON.generate(
      "id" => 123, "currency" => "MAD", "financial_status" => "pending",
      "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "total_tax" => "0.00",
      "total_discounts" => "0.00", "total_price" => "269.90",
      "shipping_address" => { "name" => "Synthetic buyer", "phone" => "0612345678", "city" => "Casablanca",
        "address1" => "Synthetic address", "country_code" => "MA" },
      "total_shipping_price_set" => { "shop_money" => { "amount" => "20.00", "currency_code" => "MAD" } },
      "line_items" => [ { "name" => "External product", "quantity" => 2, "price" => "124.95" } ]
    )
  end
  let(:headers) do
    { "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain,
      "X-Shopify-Hmac-SHA256" => Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body)) }
  end

  def intake(**overrides)
    described_class.new(connection: connection).call(body: body, headers: headers.merge(overrides))
  end

  def snapshot
    [ store.orders.count, store.customers.count, connection.external_order_receipts.count,
      connection.reload.attributes.slice("verified_at", "last_received_at", "last_error_code", "updated_at") ]
  end

  it "rejects authenticated intake before creating orders, customers, receipts or connection metadata" do
    connection
    before = snapshot

    expect { intake }.to raise_error(described_class::Error) { |error|
      expect(error.status).to eq(402)
      expect(error.message).to eq("subscription_required")
    }

    expect(snapshot).to eq(before)
  end

  it "authenticates signatures before disclosing subscription status" do
    connection
    before = snapshot

    expect { intake("X-Shopify-Hmac-SHA256" => "invalid-signature") }.to raise_error(described_class::Error) { |error|
      expect(error.status).to eq(401)
      expect(error.message).to eq("invalid_signature")
    }

    expect(snapshot).to eq(before)
  end

  it "keeps intake available to legacy merchants under their existing billing policy" do
    store.update!(subscription_required: false)

    result = intake

    expect(result.receipt.status).to eq("accepted")
    expect(result.receipt.order.store_id).to eq(store.id)
    expect(store.orders.count).to eq(1)
  end

  it "accepts an active self-service subscription through the end of its paid period" do
    store.update!(billing_status: "active", billing_period_ends_on: Date.current)

    result = intake

    expect(result.receipt.status).to eq("accepted")
    expect(result.receipt.order.total_cents).to eq(26_990)
    expect(connection.reload.verified_at).to be_present
  end

  it "denies a subscription that expired yesterday" do
    store.update!(billing_status: "active", billing_period_ends_on: Date.yesterday)
    connection
    before = snapshot

    expect { intake }.to raise_error(described_class::Error) { |error| expect(error.status).to eq(402) }

    expect(snapshot).to eq(before)
  end
end
