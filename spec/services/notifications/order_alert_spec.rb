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

  it "is queued for storefront and staff orders, but not for API imports" do
    product = store.products.create!(slug: "alert-tee", name: "Tee", price_cents: 10_000, stock: 10, status: "active", track_inventory: true)
    attrs = { name: "Synthetic buyer", phone: "0612345678", city: "Casablanca", address: "Synthetic address",
      lines: [ { product_id: product.id, quantity: 1 } ] }

    expect { Orders::Editor.new(store: store).create(attrs) }.to have_enqueued_job(NewOrderAlertJob)
    expect { Orders::Editor.new(store: store, external_effects: false).create(attrs) }.not_to have_enqueued_job(NewOrderAlertJob)
  end

  it "is queued for newly accepted connected-store webhooks, not replays or poll imports" do
    secret = "synthetic-webhook-secret"
    connection = store.store_connections.create!(provider: "shopify", name: "Synthetic Shopify",
      external_domain: "alerts-#{SecureRandom.hex(4)}.myshopify.com", webhook_secret: secret)
    payload = {
      "id" => 9_001, "currency" => "MAD", "financial_status" => "pending",
      "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "total_tax" => "0.00",
      "total_discounts" => "0.00", "total_price" => "150.00",
      "shipping_address" => { "name" => "Synthetic buyer", "phone" => "0612345678", "city" => "Casablanca",
        "address1" => "Synthetic address", "country_code" => "MA" },
      "total_shipping_price_set" => { "shop_money" => { "amount" => "20.00", "currency_code" => "MAD" } },
      "line_items" => [ { "name" => "External product", "quantity" => 1, "price" => "130.00" } ]
    }
    body = JSON.generate(payload)
    headers = {
      "X-Shopify-Topic" => "orders/create",
      "X-Shopify-Shop-Domain" => connection.external_domain,
      "X-Shopify-Hmac-SHA256" => Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
    }

    expect {
      Connections::WebhookIntake.new(connection: connection).call(body: body, headers: headers)
    }.to have_enqueued_job(NewOrderAlertJob).and have_enqueued_job(DiscordOrderNotifyJob)

    expect {
      Connections::WebhookIntake.new(connection: connection).call(body: body, headers: headers)
    }.not_to have_enqueued_job(NewOrderAlertJob)

    expect {
      Connections::WebhookIntake.new(connection: connection).import(payload.merge("id" => 9_002))
    }.not_to have_enqueued_job(NewOrderAlertJob)
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

  it "removes subscriptions that reject the configured VAPID identity" do
    user = staff(store)
    subscription = subscribe(user)
    response = Struct.new(:body, :code).new("", 401)
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::Unauthorized.new(response, "push.example.test"))

    described_class.new(order, vapid: vapid).deliver

    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "sends nothing when push keys are not configured" do
    subscribe(staff(store))

    expect(described_class.new(order, vapid: { subject: "mailto:x@example.test", public_key: nil, private_key: nil }).deliver).to eq(0)
    expect(WebPush).not_to have_received(:payload_send)
  end
end
