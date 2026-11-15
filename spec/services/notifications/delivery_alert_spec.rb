require "rails_helper"

RSpec.describe Notifications::DeliveryAlert do
  let(:password) { "synthetic-password-123" }
  let(:vapid) { { subject: "mailto:test@example.test", public_key: "public-key", private_key: "private-key" } }
  let(:store) { Store.create!(slug: "delivery-alerts-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }

  def staff
    store.users.create!(email: "staff-#{SecureRandom.hex(5)}@example.test", password: password,
      admin: true, confirmation_role: "supervisor", status: "active", name: "Synthetic")
  end

  def order
    customer = store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 25_000,
      subtotal_cents: 25_000, currency: "MAD", status: "out_for_delivery")
  end

  before { allow(WebPush).to receive(:payload_send) }

  it "pushes the carrier status label without customer details" do
    PushSubscription.create!(store: store, user: staff, endpoint: "https://push.example.test/#{SecureRandom.hex(8)}",
      p256dh: "p256dh-key", auth: "auth-secret")
    record = order

    sent = described_class.new(record, status_text: "Customer unreachable", vapid: vapid).deliver

    expect(sent).to eq(1)
    expect(WebPush).to have_received(:payload_send) do |args|
      body = JSON.parse(args[:message])
      expect(body).to include(
        "kind" => "delivery_update",
        "title" => "Delivery ##{record.number}",
        "body" => "Customer unreachable",
        "url" => "/admin/orders/#{record.id}"
      )
      expect(args[:message]).not_to include("Synthetic buyer", "0612345678", "Synthetic address")
    end
  end

  it "sends nothing when the status text is blank" do
    PushSubscription.create!(store: store, user: staff, endpoint: "https://push.example.test/#{SecureRandom.hex(8)}",
      p256dh: "p256dh-key", auth: "auth-secret")

    expect(described_class.new(order, status_text: "  ", vapid: vapid).deliver).to eq(0)
    expect(WebPush).not_to have_received(:payload_send)
  end
end
