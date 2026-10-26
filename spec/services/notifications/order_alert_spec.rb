require "rails_helper"

RSpec.describe Notifications::OrderAlert do
  let(:password) { "synthetic-password-123" }
  let(:vapid) { { subject: "mailto:test@example.test", public_key: "public-key", private_key: "private-key" } }
  let(:store) { Store.create!(slug: "alerts-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:other) { Store.create!(slug: "alerts-other-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD") }

  def staff(workspace, status: "active", admin: true, role: "supervisor")
    workspace.users.create!(email: "staff-#{SecureRandom.hex(5)}@example.test", password: password,
      admin: admin, confirmation_role: role, status: status, name: "Synthetic")
  end

  def subscribe(user)
    PushSubscription.create!(store: user.store, user: user, endpoint: "https://push.example.test/#{SecureRandom.hex(8)}",
      p256dh: "p256dh-key", auth: "auth-secret")
  end

  def order(workspace = store)
    customer = workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 25_000,
      subtotal_cents: 25_000, currency: "MAD", status: "new")
  end

  before { allow(WebPush).to receive(:payload_send) }

  it "is queued when a new order lands" do
    expect { order }.to have_enqueued_job(NewOrderAlertJob)
  end

  it "alerts active staff of the order's store only, including agents" do
    admin = staff(store)
    agent = staff(store, admin: false, role: "agent")
    suspended = staff(store, status: "suspended")
    outsider = staff(other)
    [ admin, agent, suspended, outsider ].each { |user| subscribe(user) }

    sent = described_class.new(order, vapid: vapid).deliver

    expect(sent).to eq(2)
    recipients = PushSubscription.where(user: [ admin, agent ]).pluck(:endpoint)
    expect(WebPush).to have_received(:payload_send).twice
    recipients.each do |endpoint|
      expect(WebPush).to have_received(:payload_send).with(hash_including(endpoint: endpoint, vapid: hash_including(public_key: "public-key")))
    end
  end

  it "keeps customer details out of the push payload" do
    subscribe(staff(store))

    described_class.new(order, vapid: vapid).deliver

    expect(WebPush).to have_received(:payload_send) do |args|
      body = JSON.parse(args[:message])
      expect(body["title"]).to start_with("New order #")
      expect(args[:message]).not_to include("Synthetic buyer", "0612345678", "Synthetic address")
    end
  end

  it "removes subscriptions the browser has revoked" do
    user = staff(store)
    subscription = subscribe(user)
    response = Struct.new(:body, :code).new("", 410)
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription.new(response, "push.example.test"))

    described_class.new(order, vapid: vapid).deliver

    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "sends nothing when push keys are not configured" do
    subscribe(staff(store))

    expect(described_class.new(order, vapid: { subject: "mailto:x@example.test", public_key: nil, private_key: nil }).deliver).to eq(0)
    expect(WebPush).not_to have_received(:payload_send)
  end
end
