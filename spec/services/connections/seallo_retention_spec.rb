# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloRetention do
  let(:now) { Time.utc(2027, 5, 1, 12) }
  let(:store) { Store.create!(slug: "retention-#{SecureRandom.hex(5)}", name: "Synthetic retention workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) { store.store_connections.create!(provider: "shopify", name: "Seallo", external_domain: "ret-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true, shopify_app: "seallo_connect") }
  let(:customer) { store.customers.create!(name: "Synthetic Customer", phone: "+212600000001", city: "Test City") }

  def import(status: "delivered", completed: 181.days.ago(now), connection: self.connection, customer: self.customer, external_id: SecureRandom.hex(4))
    order = connection.store.orders.create!(customer: customer, status: status, customer_name: "Synthetic Customer",
      customer_phone: customer.phone, customer_city: "Test City", customer_address: "Synthetic Street",
      total_cents: 12345, currency: "MAD", notes: "Synthetic private note")
    order.update_columns(delivered_at: (completed if status == "delivered"), cancelled_at: (completed if status == "cancelled"),
      returned_at: (completed if status == "returned"), updated_at: completed)
    connection.external_order_receipts.create!(external_id: external_id, order: order, status: "accepted", received_at: completed)
    order
  end

  it "redacts contact details once an order has been completed for 180 days, keeping money, state and replay identity" do
    order = import
    expect(described_class.call(now: now)).to eq(1)

    expect(order.reload).to have_attributes(customer_name: "Redacted", customer_address: "Redacted", notes: nil,
      total_cents: 12345, status: "delivered")
    expect(customer.reload.name).to eq("Redacted")
    expect(connection.external_order_receipts.find_by(order_id: order.id).status).to eq("accepted")
  end

  it "redacts cancelled and returned orders by their own completion date" do
    cancelled = import(status: "cancelled")
    returned = import(status: "returned")
    expect(described_class.call(now: now)).to eq(2)
    expect([ cancelled.reload.customer_name, returned.reload.customer_name ]).to all(eq("Redacted"))
  end

  it "keeps orders completed less than 180 days ago" do
    order = import(completed: 179.days.ago(now))
    expect(described_class.call(now: now)).to eq(0)
    expect(order.reload.customer_name).to eq("Synthetic Customer")
  end

  it "never touches active shipments, however old" do
    %w[new confirmed in_transit].each do |status|
      order = import(status: status)
      described_class.call(now: now)
      expect(order.reload.customer_address).to eq("Synthetic Street"), "#{status} order was redacted"
    end
  end

  it "keeps a shared buyer profile and another provider's order" do
    import
    other = store.orders.create!(customer: customer, status: "delivered", customer_name: customer.name,
      customer_phone: customer.phone, customer_city: "Test City", customer_address: "Other Street", total_cents: 99)
    other.update_columns(delivered_at: 400.days.ago(now))

    expect(described_class.call(now: now)).to eq(1)
    expect(other.reload.customer_address).to eq("Other Street")
    expect(customer.reload.name).to eq("Synthetic Customer")
  end

  it "ignores orders that did not come from Seallo Connect" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy", external_domain: "legacy-#{SecureRandom.hex(4)}.myshopify.com", shopify_oauth: true)
    order = import(connection: legacy)
    expect(described_class.call(now: now)).to eq(0)
    expect(order.reload.customer_name).to eq("Synthetic Customer")
  end

  it "also applies after the store disconnects" do
    order = import
    connection.update!(active: false)
    expect(described_class.call(now: now)).to eq(1)
    expect(order.reload.customer_name).to eq("Redacted")
  end

  it "is idempotent" do
    import
    expect(described_class.call(now: now)).to eq(1)
    expect(described_class.call(now: now)).to eq(0)
  end

  it "is scheduled daily, and the job delegates to the service" do
    schedule = YAML.safe_load(ERB.new(Rails.root.join("config/schedule.yml").read).result)
    expect(schedule.fetch("seallo_retention")).to include("class" => "SealloRetentionJob", "cron" => "17 3 * * *")

    allow(described_class).to receive(:call).and_return(0)
    SealloRetentionJob.perform_now
    expect(described_class).to have_received(:call)
  end
end
