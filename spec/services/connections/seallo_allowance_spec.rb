# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seallo Connect intake without Shopify billing" do
  let(:store) { Store.create!(slug: "seallo-allowance-#{SecureRandom.hex(5)}", name: "Synthetic quota workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic free shop", external_domain: "allowance-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
  end
  let(:payload) do
    { "id" => "1234", "currency" => "MAD", "total_price" => "100.00", "total_tax" => "0.00", "total_discounts" => "0.00",
      "financial_status" => "pending", "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "fulfillment_status" => nil,
      "total_shipping_price_set" => { "shop_money" => { "amount" => "0.00" } },
      "shipping_address" => { "name" => "Synthetic Buyer", "phone" => "+212600000099", "city" => "Casablanca", "address1" => "Synthetic Street", "country_code" => "MA" },
      "line_items" => [ { "name" => "Synthetic product", "quantity" => 1, "price" => "100.00", "total_discount" => "0.00", "requires_shipping" => true } ] }
  end

  def import(data = payload)
    Connections::WebhookIntake.new(connection: connection).import(data)
  end

  it "imports without any Shopify plan or entitlement and preserves receipt replay" do
    result = import
    expect(result.receipt).to have_attributes(status: "accepted", error_code: nil)
    expect(result.receipt.order.store).to eq(store)
    expect { expect(import.replayed).to be(true) }.not_to change(Order, :count)
    expect(connection.external_order_receipts.count).to eq(1)
    expect(store.customers.sole.orders_count).to eq(1)
  end

  it "accepts another order after a stored legacy quota and entitlement have expired" do
    connection.update!(shopify_plan_name: "Seallo Basic", shopify_order_limit: 1,
      shopify_billing_period_start: 40.days.ago, shopify_billing_period_end: 10.days.ago, shopify_entitled_until: 1.day.ago)
    expect(import.receipt.status).to eq("accepted")
    expect(import(payload.merge("id" => "1235")).receipt.status).to eq("accepted")
    expect(store.orders.count).to eq(2)
    expect(connection.external_order_receipts.where(status: "accepted").count).to eq(2)
  end

  it "authenticates signed webhooks without requiring a Shopify plan" do
    secret = "synthetic-free-integration-secret"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SEALLO_SHOPIFY_CLIENT_SECRET").and_return(secret)
    body = JSON.generate(payload)
    headers = { "X-Shopify-Hmac-SHA256" => Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body)),
      "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain }
    result = Connections::WebhookIntake.new(connection: connection).call(body: body, headers: headers)
    expect(result.receipt.status).to eq("accepted")
    expect(import.replayed).to be(true)
    expect(connection.external_order_receipts.count).to eq(1)
  end

  it "still denies imports when Morea workspace operational access expires" do
    connection
    store.update!(subscription_required: true, billing_status: "past_due", trial_ends_at: nil, billing_period_ends_on: 1.day.ago)
    expect { import }.to raise_error(Connections::WebhookIntake::Error) do |error|
      expect([ error.message, error.status ]).to eq([ "subscription_required", 402 ])
    end
    expect(store.orders.count).to eq(0)
    expect(connection.external_order_receipts.count).to eq(0)
  end
end
