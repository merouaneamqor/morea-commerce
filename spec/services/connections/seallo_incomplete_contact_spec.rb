# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seallo imports with incomplete contact details" do
  let(:store) { Store.create!(slug: "contact-#{SecureRandom.hex(5)}", name: "Synthetic contact workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(name: "Synthetic Shopify", provider: "shopify", shopify_app: "seallo_connect", shopify_oauth: true,
      external_domain: "contact-#{SecureRandom.hex(5)}.myshopify.com", shopify_plan_name: "Seallo Premium", shopify_order_limit: nil,
      shopify_billing_period_start: 1.day.ago, shopify_billing_period_end: 29.days.from_now, shopify_entitled_until: 1.hour.from_now)
  end
  let(:payload) do
    { "id" => "1234", "currency" => "MAD", "total_price" => "30055.00", "total_tax" => "0.00", "total_discounts" => "0.00",
      "financial_status" => "pending", "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "cancelled_at" => nil, "fulfillment_status" => nil,
      "total_shipping_price_set" => { "shop_money" => { "amount" => "55.00" } },
      "shipping_address" => { "name" => "Synthetic Buyer", "phone" => nil, "city" => "Casablanca", "address1" => "Synthetic Street", "country_code" => "MA" },
      "line_items" => [ { "name" => "Synthetic product", "quantity" => 1, "price" => "30000.00", "total_discount" => "0.00", "requires_shipping" => true } ] }
  end

  def intake(data = payload)
    Connections::WebhookIntake.new(connection: connection).import(data)
  end

  it "imports the reviewer's missing-phone shape visibly without creating a fake customer" do
    result = intake
    expect(result.receipt).to have_attributes(status: "accepted", error_code: nil)
    order = result.receipt.order
    expect(order).to have_attributes(status: "new", customer_name: "Synthetic Buyer", customer_phone: nil,
      customer_id: nil, total_cents: 3_005_500, shipping_cents: 5_500, import_contact_issues: [ "phone" ])
    expect(order).to be_contact_review_required
    expect(order.order_items.sole).to have_attributes(product_name: "Synthetic product", quantity: 1, unit_price_cents: 3_000_000)
    expect(store.customers.count).to eq(0)
    expect(connection.reload.last_error_code).to be_nil
    expect(Connections::SealloAllowance.used(connection)).to eq(1)
  end

  it "preserves separate phone-less orders without merging buyers or duplicating replayed orders" do
    first = intake.receipt.order
    second = intake(payload.deep_merge("id" => "1235", "shipping_address" => { "name" => "Other Synthetic Buyer" })).receipt.order
    expect(second.id).not_to eq(first.id)
    expect(store.orders.pluck(:customer_name)).to contain_exactly("Synthetic Buyer", "Other Synthetic Buyer")
    expect(store.customers.count).to eq(0)
    expect { expect(intake.replayed).to be(true) }.not_to change(Order, :count)
    expect(Connections::SealloAllowance.used(connection)).to eq(2)
  end

  it "recovers a previously rejected external receipt without allocating another import identity" do
    original = connection.external_order_receipts.create!(external_id: payload.fetch("id"), status: "rejected", error_code: "invalid_contact", received_at: 1.hour.ago)
    expect { intake }.to change(Order, :count).by(1).and change(ExternalOrderReceipt, :count).by(0)
    expect(original.reload).to have_attributes(status: "accepted", error_code: nil)
    expect(original.order.import_contact_issues).to eq([ "phone" ])
  end

  it "marks each absent contact field while preserving the rest of the imported order" do
    payload["shipping_address"].merge!("name" => nil, "city" => " ", "address1" => nil)
    order = intake.receipt.order
    expect(order.import_contact_issues).to contain_exactly("name", "phone", "city", "address")
    expect(order.customer_name).to be_nil
    expect(order.customer_city).to be_nil
    expect(order.customer_address).to be_nil
    expect(order.customer).to be_nil
  end

  it "keeps malformed phone text visible for review without matching an existing profile" do
    store.customers.create!(name: "Existing Synthetic Buyer", phone: "0612345678", city: "Rabat")
    payload["shipping_address"]["phone"] = "123"
    order = intake.receipt.order
    expect(order).to have_attributes(customer_phone: "123", customer_id: nil, import_contact_issues: [ "phone" ])
    expect(store.customers.sole.name).to eq("Existing Synthetic Buyer")
  end

  it "uses an existing valid customer without erasing their city when the imported city is absent" do
    customer = store.customers.create!(name: "Synthetic Buyer", phone: "0612345678", city: "Rabat")
    payload["shipping_address"].merge!("phone" => "0612345678", "city" => nil)
    order = intake.receipt.order
    expect(order).to have_attributes(customer_id: customer.id, customer_city: nil, import_contact_issues: [ "city" ])
    expect(customer.reload).to have_attributes(city: "Rabat", orders_count: 1)
  end

  it "uses order-level phone for a signed webhook without marking complete contact for review" do
    payload["phone"] = "+212 600 000 123"
    secret = "synthetic-contact-webhook-secret"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SEALLO_SHOPIFY_CLIENT_SECRET").and_return(secret)
    body = JSON.generate(payload)
    headers = { "X-Shopify-Hmac-SHA256" => Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body)),
      "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain }
    result = Connections::WebhookIntake.new(connection: connection).call(body: body, headers: headers)
    expect(result.receipt.order).to have_attributes(customer_phone: "+212600000123", import_contact_issues: [])
    expect(result.receipt.order.customer.phone).to eq("+212600000123")
    expect(intake.replayed).to be(true)
  end

  it "still rejects malformed contact types and excessively long fields" do
    [ { "phone" => [] }, { "phone" => "1" * 256 }, { "name" => {} }, { "city" => false }, { "address1" => "x" * 256 } ].each_with_index do |bad, index|
      result = intake(payload.deep_merge("id" => "bad-#{index}", "shipping_address" => bad))
      expect(result.receipt).to have_attributes(status: "rejected", error_code: "invalid_contact", order_id: nil)
    end
    expect(store.orders.count).to eq(0)
    expect(store.customers.count).to eq(0)
  end

  it "keeps noncontact eligibility restrictions and unsupported shipping addresses" do
    [ { "financial_status" => "paid" }, { "total_tax" => "1.00" }, { "total_discounts" => "1.00" },
      { "currency" => "USD" }, { "shipping_address" => payload.fetch("shipping_address").merge("country_code" => "US") },
      { "shipping_address" => nil } ].each_with_index do |change, index|
      result = intake(payload.merge("id" => "unsupported-#{index}").merge(change))
      expect(result.receipt.status).to eq("rejected")
      expect(result.receipt.order_id).to be_nil
    end
    expect(store.orders.count).to eq(0)
  end

  it "continues rejecting incomplete contact for the legacy Shopify importer" do
    connection.update!(shopify_app: nil)
    expect(intake.receipt).to have_attributes(status: "rejected", error_code: "invalid_contact", order_id: nil)
    expect(store.orders.count).to eq(0)
  end
end
