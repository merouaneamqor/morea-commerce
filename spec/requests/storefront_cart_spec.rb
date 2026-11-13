# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront cart", type: :request do
  let(:store) do
    Store.create!(slug: "cart-#{SecureRandom.hex(4)}", name: "Cart Store", currency: "MAD", storefront_enabled: true)
  end
  let!(:product) do
    store.products.create!(name: "Hoodie", slug: "hoodie", status: "active", price_cents: 8_000, stock: 10)
  end

  before { host! "#{store.slug}.#{Store.base_domain}" }

  it "adds, updates, and removes a line" do
    post "/en/cart/add_item", params: { product_id: product.id, quantity: 2 }
    expect(response).to redirect_to("/en/cart")

    cart = store.carts.order(:id).last
    item = cart.cart_items.sole
    expect(item).to have_attributes(product_id: product.id, quantity: 2, unit_price_cents: 8_000)

    patch "/en/cart/update_item", params: { item_id: item.id, quantity: 5 }
    expect(response).to redirect_to("/en/cart")
    expect(item.reload.quantity).to eq(5)

    delete "/en/cart/remove_item", params: { item_id: item.id }
    expect(response).to redirect_to("/en/cart")
    expect(cart.cart_items.reload).to be_empty
  end

  it "clamps quantity between 1 and 99" do
    post "/en/cart/add_item", params: { product_id: product.id, quantity: 0 }
    item = store.carts.order(:id).last.cart_items.sole
    expect(item.quantity).to eq(1)

    patch "/en/cart/update_item", params: { item_id: item.id, quantity: 250 }
    expect(item.reload.quantity).to eq(99)
  end

  it "rejects inactive products and foreign-store product ids" do
    draft = store.products.create!(name: "Draft", slug: "draft", status: "draft", price_cents: 1_000)
    foreign = Store.create!(slug: "fx-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD", storefront_enabled: true)
    stranger = foreign.products.create!(name: "Secret", slug: "secret", status: "active", price_cents: 1_000)

    expect {
      post "/en/cart/add_item", params: { product_id: draft.id, quantity: 1 }
    }.not_to change { CartItem.count }
    expect(response).to have_http_status(:not_found)

    expect {
      post "/en/cart/add_item", params: { product_id: stranger.id, quantity: 1 }
    }.not_to change { store.carts.flat_map { |c| c.cart_items.reload }.size }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps carts isolated across tenant hosts that share a session cookie domain" do
    other = Store.create!(slug: "iso-#{SecureRandom.hex(4)}", name: "Iso", currency: "MAD", storefront_enabled: true)
    other_product = other.products.create!(name: "Other Hoodie", slug: "other-hoodie", status: "active", price_cents: 4_000)

    post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }
    expect(store.carts.order(:id).last.cart_items.sole.product_id).to eq(product.id)

    host! "#{other.slug}.#{Store.base_domain}"
    get "/en/cart"
    expect(response).to have_http_status(:ok)
    expect(other.carts.flat_map { |c| c.cart_items.reload }).to be_empty

    post "/en/cart/add_item", params: { product_id: other_product.id, quantity: 1 }
    expect(other.carts.order(:id).last.cart_items.sole.product_id).to eq(other_product.id)
    expect(store.carts.flat_map { |c| c.cart_items.reload }.map(&:product_id)).to eq([ product.id ])
  end
end
