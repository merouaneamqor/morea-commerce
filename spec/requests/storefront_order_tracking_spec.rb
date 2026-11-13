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

  it "shows an order by number on the owning tenant host" do
    get "/en/orders/#{order.number}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.number)
  end

  it "looks up an order when the phone last 8 digits match" do
    post "/en/orders/lookup", params: { number: order.number, phone: "0612345678" }
    expect(response).to redirect_to("/en/orders/#{order.number}")
  end

  it "refuses lookup with the wrong phone" do
    post "/en/orders/lookup", params: { number: order.number, phone: "0699999999" }
    expect(response).to redirect_to("/en/orders/track")
    expect(flash[:alert]).to be_present
  end

  it "does not expose another tenant's order number" do
    foreign = Store.create!(slug: "trkfx-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD", storefront_enabled: true)
    foreign_customer = foreign.customers.create!(name: "Other", phone: "+212612345678", city: "Rabat")
    foreign_order = foreign.orders.create!(
      customer: foreign_customer,
      customer_name: "Other",
      customer_phone: "+212612345678",
      customer_city: "Rabat",
      customer_address: "Ave 2",
      payment_method: "cod",
      status: "new",
      currency: "MAD",
      subtotal_cents: 5_000,
      total_cents: 5_000
    )

    get "/en/orders/#{foreign_order.number}"
    expect(response).to have_http_status(:not_found)

    post "/en/orders/lookup", params: { number: foreign_order.number, phone: "0612345678" }
    expect(response).to redirect_to("/en/orders/track")
  end
end
