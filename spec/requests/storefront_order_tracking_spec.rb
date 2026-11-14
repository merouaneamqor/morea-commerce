# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront order tracking", type: :request do
  let(:store) do
    Store.create!(slug: "trk-#{SecureRandom.hex(4)}", name: "Track Store", currency: "MAD", storefront_enabled: true)
  end
  let(:customer) { store.customers.create!(name: "Buyer", phone: "+212612345678", city: "Casablanca") }
  let!(:order) do
    store.orders.create!(
      customer: customer,
      customer_name: "Buyer",
      customer_phone: "+212612345678",
      customer_city: "Casablanca",
      customer_address: "Rue 1",
      payment_method: "cod",
      status: "new",
      currency: "MAD",
      subtotal_cents: 10_000,
      shipping_cents: 0,
      total_cents: 10_000
    )
  end

  before { host! "#{store.slug}.#{Store.base_domain}" }

  it "hides an order when the shopper only knows its number" do
    get "/en/orders/#{order.number}"
    expect(response).to have_http_status(:not_found)
  end

  it "opens the private receipt after matching the full normalized phone" do
    post "/en/orders/lookup", params: { number: order.number, phone: "06 12 34 56 78" }
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to("/en/orders/#{order.number}")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.number)
    expect(response.headers["Cache-Control"]).to include("private", "no-store")
  end

  [ "", "12345678", "0712345678" ].each do |phone|
    it "refuses a phone that does not match in full (#{phone.inspect})" do
      post "/en/orders/lookup", params: { number: order.number, phone: phone }
      expect(response).to redirect_to("/en/orders/track")
      expect(flash[:alert]).to be_present
      get "/en/orders/#{order.number}"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "keeps a verified session and tracking lookup scoped to the owning tenant" do
    foreign = Store.create!(slug: "trkfx-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD", storefront_enabled: true)
    foreign_customer = foreign.customers.create!(name: "Other", phone: "+212712345678", city: "Rabat")
    foreign_order = foreign.orders.create!(
      number: order.number,
      customer: foreign_customer,
      customer_name: "Other",
      customer_phone: foreign_customer.phone,
      customer_city: "Rabat",
      customer_address: "Ave 2",
      payment_method: "cod",
      status: "new",
      currency: "MAD",
      subtotal_cents: 5_000,
      total_cents: 5_000
    )

    post "/en/orders/lookup", params: { number: foreign_order.number, phone: foreign_customer.phone }
    expect(response).to redirect_to("/en/orders/track")

    post "/en/orders/lookup", params: { number: order.number, phone: "0612345678" }
    expect(response).to redirect_to("/en/orders/#{order.number}")

    host! "#{foreign.slug}.#{Store.base_domain}"
    get "/en/orders/#{foreign_order.number}"
    expect(response).to have_http_status(:not_found)
  end
end
