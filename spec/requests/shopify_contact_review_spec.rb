# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Shopify imported orders needing contact review", type: :request do
  let(:password) { "Synthetic-contact-password-123" }
  let(:store) { Store.create!(slug: "contact-review-#{SecureRandom.hex(5)}", name: "Synthetic contact desk", currency: "MAD") }
  let(:manager) { store.users.create!(email: "manager-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent") }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic Seallo shop", external_domain: "contact-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_plan_name: "Seallo Basic", shopify_order_limit: 30,
      shopify_entitled_until: 10.minutes.from_now, shopify_billing_period_start: 1.day.ago, shopify_billing_period_end: 29.days.from_now)
  end
  let(:payload) do
    {
      "id" => "review-order-1001", "currency" => "MAD", "financial_status" => "pending",
      "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "cancelled_at" => nil, "fulfillment_status" => nil,
      "total_price" => "30055.00", "total_tax" => "0.00", "total_discounts" => "0.00",
      "total_shipping_price_set" => { "shop_money" => { "amount" => "55.00" } },
      "shipping_address" => { "name" => "Synthetic Review Buyer", "phone" => nil, "city" => "Casablanca",
        "address1" => "Synthetic review street", "country_code" => "MA" },
      "line_items" => [ { "name" => "Synthetic dress", "quantity" => 1, "price" => "30000.00", "requires_shipping" => true,
        "fulfillment_status" => nil, "total_discount" => "0.00" } ]
    }
  end
  let(:contact) { { name: "Synthetic Review Buyer", phone: "0612345678", city: "Casablanca", address: "Synthetic review street", district: "Synthetic district" } }

  before do
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise("Unexpected provider operation")
    allow(Connections::SealloBridge).to receive(:graphql).and_raise("Unexpected provider operation")
  end

  def browser(workspace = store)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "#{workspace.slug}.#{Store.base_domain}"
    end
  end

  def sign_in(session, user)
    session.post "/admin/login", params: { email: user.email, password: password, locale: "en" }
    expect(session.response).to have_http_status(:redirect)
  end

  def import_order
    result = Connections::WebhookIntake.new(connection: connection).import(payload)
    expect(result.receipt.status).to eq("accepted")
    result.receipt.order
  end

  def correction_path(order)
    "/admin/orders/#{order.id}/complete_import_contact"
  end

  def correction_form(session, order)
    Nokogiri::HTML(session.response.body).at_css("form[action='#{correction_path(order)}']")
  end

  it "shows the reviewer's phone-less order, preserves the import, and allows confirmation only after a manager completes contact" do
    order = import_order
    receipt = order.external_order_receipt
    item = order.order_items.sole
    expect(order).to have_attributes(status: "new", total_cents: 3_005_500, shipping_cents: 5_500, customer_phone: nil)
    expect(order.import_contact_issues).to include("phone")
    expect(order.customer).to be_nil
    expect(store.customers.count).to eq(0)

    session = browser
    sign_in(session, manager)
    session.get "/admin/orders", params: { locale: "en" }
    expect(session.response).to have_http_status(:ok)
    expect(session.response.body).to include(order.number)
    expect(Nokogiri::HTML(session.response.body).css("[role='alert']").text).to match(/phone/i)
    session.get "/admin/orders/#{order.id}", params: { locale: "en" }
    expect(session.response).to have_http_status(:ok)
    expect(correction_form(session, order)).to be_present

    session.patch "/admin/orders/#{order.id}/transition", params: { to_status: "confirmed", locale: "en" }
    expect(session.response).to have_http_status(:redirect)
    expect(order.reload.status).to eq("new")
    expect(order.confirmed_at).to be_nil

    session.patch correction_path(order), params: { contact: contact, locale: "en" }
    expect(session.response).to have_http_status(:redirect)
    expect(order.reload.import_contact_issues).to eq([])
    expect(order.customer_phone).to eq("0612345678")
    expect(order.customer).to have_attributes(store_id: store.id, phone: "0612345678", orders_count: 1)
    expect(order.external_order_receipt.id).to eq(receipt.id)
    expect(order.order_items.sole.id).to eq(item.id)
    expect(order).to have_attributes(total_cents: 3_005_500, shipping_cents: 5_500)
    expect(order).not_to be_editable

    session.patch "/admin/orders/#{order.id}/transition", params: { to_status: "confirmed", locale: "en" }
    expect(session.response).to have_http_status(:redirect)
    expect(order.reload.status).to eq("confirmed")
    expect(order.confirmed_at).to be_present

    replay = Connections::WebhookIntake.new(connection: connection).import(payload)
    expect(replay.replayed).to be(true)
    expect(replay.receipt.id).to eq(receipt.id)
    expect(store.orders.count).to eq(1)
    expect(store.customers.count).to eq(1)
    expect(order.reload.import_contact_issues).to eq([])
    expect(order.customer_phone).to eq("0612345678")
  end

  it "lets an agent see the alert but prevents contact correction and starting a call" do
    order = import_order
    session = browser
    sign_in(session, agent)
    session.get "/admin/orders/#{order.id}", params: { locale: "en" }
    expect(session.response).to have_http_status(:ok)
    expect(Nokogiri::HTML(session.response.body).css("[role='alert']").text).to match(/phone/i)
    expect(correction_form(session, order)).to be_nil

    session.patch correction_path(order), params: { contact: contact, locale: "en" }
    expect(session.response).to have_http_status(:redirect)
    expect(order.reload).to be_contact_review_required
    expect(order.customer_phone).to be_nil

    session.post "/admin/confirmations/#{order.id}/call", as: :json
    expect(session.response).to have_http_status(:unprocessable_content)
    expect(order.reload.order_confirmation&.call_started_at).to be_nil
    expect(ConfirmationAttempt.where(store: store).count).to eq(0)
  end

  it "keeps malformed corrections from creating a customer or clearing the warning" do
    order = import_order
    session = browser
    sign_in(session, manager)
    [ contact.merge(phone: ""), contact.merge(phone: "invalid"), contact.merge(address: "") ].each do |invalid|
      session.patch correction_path(order), params: { contact: invalid, locale: "en" }
      expect(session.response).to have_http_status(:redirect)
      expect(order.reload.import_contact_issues).to include("phone")
      expect(order.customer_phone).to be_nil
      expect(store.customers.count).to eq(0)
    end
  end

  it "rejects signed-out and foreign-workspace correction requests" do
    order = import_order
    visitor = browser
    visitor.patch correction_path(order), params: { contact: contact, locale: "en" }
    expect(visitor.response).to have_http_status(:redirect)
    expect(URI(visitor.response.location).path).to eq("/admin/login")

    other = Store.create!(slug: "foreign-contact-#{SecureRandom.hex(5)}", name: "Other synthetic desk", currency: "MAD")
    outsider = other.users.create!(email: "foreign-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    foreign = browser(other)
    sign_in(foreign, outsider)
    foreign.patch correction_path(order), params: { contact: contact, locale: "en" }
    expect(foreign.response).to have_http_status(:not_found)
    expect(order.reload).to be_contact_review_required
    expect(order.customer_phone).to be_nil
    expect(other.customers.count).to eq(0)
  end

  %w[fr en ar].each do |locale|
    it "renders contact alerts and the correction form in #{locale}" do
      order = import_order
      session = browser
      sign_in(session, manager)
      session.get "/admin/orders/#{order.id}", params: { locale: locale }
      expect(session.response).to have_http_status(:ok)
      expect(session.response.body).not_to match(/translation missing|translation_missing/i)
      expect(Nokogiri::HTML(session.response.body).css("[role='alert']")).not_to be_empty
      expect(correction_form(session, order)).to be_present
    end
  end
end
