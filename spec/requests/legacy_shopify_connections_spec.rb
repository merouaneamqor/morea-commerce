# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Shopify connections after Seallo Connect", type: :request do
  let(:password) { "synthetic-legacy-shopify-password-123" }
  let(:store) { Store.create!(slug: "legacy-shopify-#{SecureRandom.hex(5)}", name: "Synthetic legacy workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "legacy-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:shop) { "legacy-#{SecureRandom.hex(5)}.myshopify.com" }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic standalone shop", external_domain: shop, shopify_oauth: true)
  end

  before { host! Store.base_domain }

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: staff.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "no longer serves the standalone Shopify app entry or its OAuth callback" do
    sign_in
    get "/admin/shopify", params: { shop: shop }
    expect(response).to have_http_status(:not_found)
    get "/admin/shopify/callback", params: { shop: shop, code: "synthetic-code", state: "synthetic-state" }
    expect(response).to have_http_status(:not_found)
  end

  it "refuses to create a Shopify connection from the store form" do
    sign_in
    expect {
      post "/admin/store_connections", params: { store_connection: { provider: "shopify", name: "Synthetic", external_domain: shop } }
    }.not_to change(StoreConnection, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "offers no authorization operation for an existing standalone connection" do
    connection
    sign_in
    patch "/admin/store_connections/#{connection.id}", params: { operation: "authorize_shopify" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(connection.reload.shopify_oauth_state_digest).to be_nil
  end

  it "keeps an existing standalone connection visible and lets its owner disconnect it" do
    connection
    sign_in
    get "/admin/store_connections/#{connection.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(connection.name)
    expect(response.body).not_to include("authorize_shopify")

    patch "/admin/store_connections/#{connection.id}", params: { operation: "disconnect" }
    expect(response).to redirect_to("/admin/store_connections/#{connection.id}")
    expect(connection.reload).not_to be_active
  end
end
