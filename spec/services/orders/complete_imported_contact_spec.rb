require "rails_helper"

RSpec.describe Orders::CompleteImportedContact do
  let(:store) { Store.create!(slug: "contact-service-#{SecureRandom.hex(4)}", name: "Synthetic contact workspace") }
  let(:actor) { store.users.create!(email: "contact-#{SecureRandom.hex(4)}@example.test", password: "Synthetic-contact-password-123!", admin: true) }
  let(:connection) { store.store_connections.create!(provider: "shopify", name: "Synthetic source", external_domain: "contact-service.myshopify.com", shopify_app: "seallo_connect", shopify_oauth: true) }
  let(:order) do
    store.orders.create!(customer_name: "Synthetic buyer", customer_city: "Casablanca", customer_address: "Synthetic street",
      import_contact_issues: [ "phone" ], currency: "MAD").tap do |row|
      connection.external_order_receipts.create!(external_id: "12345", status: "accepted", received_at: Time.current, order: row)
    end
  end
  let(:contact) { { name: "Synthetic buyer", phone: "0612345678", city: "Casablanca", address: "Synthetic street" } }
  subject(:service) { described_class.new(store: store, user: actor) }

  it "rechecks a stale actor's authorization before repairing an order" do
    service
    User.find(actor.id).update!(admin: false)
    expect { service.call(order: order, attrs: contact) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(order.reload).to be_contact_review_required
  end

  it "matches only this workspace's customer and adjusts its count once" do
    other = Store.create!(slug: "contact-other-#{SecureRandom.hex(4)}", name: "Other synthetic workspace")
    foreign = other.customers.create!(name: "Other buyer", phone: contact[:phone])
    local = store.customers.create!(name: contact[:name], phone: contact[:phone], orders_count: 2)
    service.call(order: order, attrs: contact)
    expect(order.reload.customer).to eq(local)
    expect(local.reload.orders_count).to eq(3)
    expect(foreign.reload.orders_count).to eq(0)
    expect { service.call(order: order, attrs: contact) }.to raise_error(described_class::Error)
    expect(local.reload.orders_count).to eq(3)
  end

  it "blocks status writes at model and database boundaries but allows cancellation" do
    expect { order.transition_to!("confirmed") }.to raise_error(ArgumentError)
    expect(order.reload.status).to eq("new")
    expect(order.update(status: "confirmed")).to be(false)
    order.reload
    expect do
      Order.transaction(requires_new: true) { order.update_columns(status: "confirmed") }
    end.to raise_error(ActiveRecord::StatementInvalid)
    order.reload.transition_to!("cancelled", reason: "Synthetic cancellation")
    expect(order.reload.status).to eq("cancelled")
    expect { service.call(order: order, attrs: contact) }.to raise_error(described_class::Error)
  end

  it "preserves strict contact requirements for ordinary orders" do
    regular = store.orders.new(customer_name: "Synthetic buyer", customer_city: "Casablanca", customer_address: "Synthetic street")
    expect(regular).not_to be_valid
    expect(regular.errors.attribute_names).to include(:customer, :customer_phone)
  end

  it "redacts a cancelled imported order without requiring a fabricated buyer profile" do
    order.transition_to!("cancelled")
    request = ShopifyPrivacyRequest.create!(store_connection: connection, topic: "customers/redact", event_key: SecureRandom.hex(16),
      identifiers: { "shop_domain" => connection.external_domain, "order_ids" => [ "12345" ] })
    expect { request.process! }.not_to raise_error
    expect(order.reload.customer_name).to eq("Redacted")
    expect(order.customer).to be_nil
  end
end
