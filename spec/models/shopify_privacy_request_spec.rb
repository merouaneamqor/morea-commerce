# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShopifyPrivacyRequest do
  let(:store) { Store.create!(slug: "privacy-model-#{SecureRandom.hex(5)}", name: "Synthetic privacy workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) { store.store_connections.create!(provider: "shopify", name: "Seallo", external_domain: "model-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true, shopify_app: "seallo_connect") }
  let(:customer) { store.customers.create!(name: "Synthetic Customer", phone: "+212600000001", city: "Test City") }

  def imported_order(external_id: "10", status: "delivered", connection: self.connection, customer: self.customer)
    order = connection.store.orders.create!(customer: customer, status: status, customer_name: "Synthetic Customer",
      customer_phone: customer.phone, customer_city: "Test City", customer_address: "Synthetic Street",
      total_cents: 12345, currency: "MAD", notes: "Synthetic private note")
    connection.external_order_receipts.create!(external_id: external_id, order: order, status: "accepted", received_at: Time.current)
    order
  end

  def privacy(topic = "customers/redact", ids: [ "10" ])
    described_class.create!(store_connection: connection, event_key: SecureRandom.hex(32), topic: topic,
      identifiers: { "order_ids" => ids, "customer_id" => "123", "request_id" => "456" })
  end

  it "anonymizes terminal imported snapshots while retaining money, state and replay identity" do
    order = imported_order
    request = privacy
    request.process!
    expect(request.reload.status).to eq("completed")
    expect(request.identifiers_ciphertext).to be_nil
    expect(order.reload).to have_attributes(customer_name: "Redacted", customer_address: "Redacted", total_cents: 12345, status: "delivered", notes: nil)
    expect(customer.reload.name).to eq("Redacted")
    expect(connection.external_order_receipts.find_by(external_id: "10").order_id).to eq(order.id)
    request.process!
    expect(order.reload.total_cents).to eq(12345)
  end

  it "retains active shipping details for review without changing stock or state" do
    order = imported_order(status: "in_transit")
    request = privacy
    request.process!
    expect(request.reload).to have_attributes(status: "needs_review", error_code: "retained_business_records")
    expect(order.reload.customer_address).to eq("Synthetic Street")
    expect(order.status).to eq("in_transit")
    expect { request.complete! }.to raise_error(ArgumentError)
  end

  it "does not permit manual completion to discard an unprocessed redaction" do
    request = privacy
    expect { request.complete! }.to raise_error(ArgumentError)
    expect(request.reload.status).to eq("pending")
    expect(request.identifiers["order_ids"]).to eq([ "10" ])
  end

  it "does not erase a shared customer profile or another provider's order" do
    imported_order
    unrelated = store.orders.create!(customer: customer, status: "delivered", customer_name: customer.name,
      customer_phone: customer.phone, customer_city: "Test City", customer_address: "Other Street", total_cents: 99)
    request = privacy
    request.process!
    expect(request.reload.status).to eq("needs_review")
    expect(customer.reload.name).to eq("Synthetic Customer")
    expect(unrelated.reload.customer_address).to eq("Other Street")
  end

  it "exports only requested IDs owned by this connection and awaits a secure response" do
    order = imported_order
    imported_order(external_id: "20")
    request = privacy("customers/data_request")
    request.process!
    expect(request.reload.status).to eq("needs_review")
    expect(request.export_data[:orders].map { |entry| entry[:order]["id"] }).to eq([ order.id ])
    request.complete!
    expect(request.reload.status).to eq("completed")
    expect(request.identifiers_ciphertext).to be_nil
  end

  it "leaves a foreign workspace's overlapping Shopify order ID untouched" do
    imported_order
    foreign_store = Store.create!(slug: "privacy-foreign-#{SecureRandom.hex(5)}", name: "Foreign synthetic workspace", currency: "MAD", storefront_enabled: false)
    foreign_customer = foreign_store.customers.create!(name: "Other Synthetic Customer", phone: "+212600000002", city: "Other City")
    foreign_connection = foreign_store.store_connections.create!(provider: "shopify", name: "Foreign Seallo",
      external_domain: "foreign-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true, shopify_app: "seallo_connect")
    foreign_order = imported_order(connection: foreign_connection, customer: foreign_customer)
    request = privacy
    request.process!
    expect(request.reload.status).to eq("completed")
    expect(foreign_order.reload.customer_address).to eq("Synthetic Street")
    expect(foreign_customer.reload.name).to eq("Other Synthetic Customer")
  end

  it "shop redaction disconnects credentials and preserves financial records" do
    order = imported_order
    connection.update!(shopify_access_token: "synthetic-token", shopify_access_token_expires_at: 1.hour.from_now)
    request = privacy("shop/redact", ids: [])
    request.process!
    expect(connection.reload.active?).to be(false)
    expect(connection.shopify_access_token_ciphertext).to be_nil
    expect(order.reload.total_cents).to eq(12345)
    expect(order.customer_name).to eq("Redacted")
  end
end
