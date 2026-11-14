# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront COD checkout", type: :request do
  include ActiveJob::TestHelper

  let(:store) do
    Store.create!(
      slug: "chk-#{SecureRandom.hex(4)}",
      name: "Checkout Store",
      currency: "MAD",
      storefront_enabled: true,
      shipping_cents: 3_000
    )
  end
  let!(:product) do
    store.products.create!(
      name: "Tracksuit",
      slug: "tracksuit",
      status: "active",
      price_cents: 10_000,
      stock: 5,
      track_inventory: true
    )
  end

  before { host! "#{store.slug}.#{Store.base_domain}" }

  def add_to_cart(qty: 1)
    post "/en/cart/add_item", params: { product_id: product.id, quantity: qty }
  end

  def place_order(extra: {})
    post "/en/checkout", params: {
      checkout: {
        name: "Buyer",
        phone: "0612345678",
        city: "Casablanca",
        address: "Rue 1",
        privacy_accepted: "1",
        age_confirmed: "1"
      }.merge(extra)
    }
  end

  it "places a COD order as new without reserving stock, clears the cart, and enqueues alerts" do
    add_to_cart(qty: 2)

    order = nil
    expect {
      place_order
      order = store.orders.order(:id).last
    }.to change { store.orders.count }.by(1)
      .and have_enqueued_job(OrderStatusJob)
      .and have_enqueued_job(NewOrderAlertJob)

    expect(response).to redirect_to("/en/orders/#{order.number}")
    expect(order).to have_attributes(
      payment_method: "cod",
      status: "new",
      customer_name: "Buyer",
      total_cents: 23_000
    )
    expect(order.order_items.sole).to have_attributes(product_id: product.id, quantity: 2, unit_price_cents: 10_000)
    expect(product.reload.stock).to eq(5)
    expect(order.inventory_movements).to be_empty

    get "/en/cart"
    expect(response).to have_http_status(:ok)
    expect(store.carts.flat_map { |c| c.cart_items.reload }.sum(&:quantity)).to eq(0)
  end

  it "rejects an invalid phone and leaves the cart untouched" do
    add_to_cart
    expect { place_order(extra: { phone: "12" }) }.not_to change { store.orders.count }
    expect(response).to have_http_status(:unprocessable_content)
    expect(store.carts.flat_map(&:cart_items).sum(&:quantity)).to eq(1)
  end

  it "places the same COD flow under /fr and /ar" do
    %w[fr ar].each do |locale|
      product_copy = store.products.create!(
        name: "Item #{locale}",
        slug: "item-#{locale}-#{SecureRandom.hex(3)}",
        status: "active",
        price_cents: 5_000,
        stock: 3,
        track_inventory: true
      )
      post "/#{locale}/cart/add_item", params: { product_id: product_copy.id, quantity: 1 }
      post "/#{locale}/checkout", params: {
        checkout: {
          name: "Buyer",
          phone: "0612345678",
          city: "Rabat",
          address: "Avenue 2",
          privacy_accepted: "1",
          age_confirmed: "1"
        }
      }
      order = store.orders.order(:id).last
      expect(response).to redirect_to("/#{locale}/orders/#{order.number}")
      expect(order).to have_attributes(payment_method: "cod", status: "new")
      expect(response.headers["Location"]).to include("/#{locale}/")
    end
  end

  it "redirects empty checkout to the cart" do
    get "/en/checkout"
    expect(response).to redirect_to("/en/cart")
  end
end
