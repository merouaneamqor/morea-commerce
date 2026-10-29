# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Shopify app home", type: :request do
  let(:password) { "synthetic-app-home-password" }
  let(:shop) { "synthetic-app-home.myshopify.com" }
  let(:store) { Store.create!(slug: "app-home-#{SecureRandom.hex(5)}", name: "Synthetic app workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "app-home-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  before { host! Store.base_domain }

  def sign_in(user = staff)
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "returns to the app after login, carrying only a valid shop hint" do
    get "/admin/shopify", params: { shop: shop, hmac: "untrusted", store_id: 999_999, host: "untrusted.example" }
    expect(response).to redirect_to("/admin/login")
    sign_in
    expect(response).to redirect_to("/admin/shopify?shop=#{shop}")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name, shop)
    expect(StoreConnection.count).to eq(0)
  end

  it "shows only workspace connections and never authorizes on a GET" do
    own = store.store_connections.create!(name: "Owned Shopify", provider: "shopify", external_domain: shop, shopify_oauth: true)
    other = Store.create!(slug: "app-other-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD")
    foreign = other.store_connections.create!(name: "Foreign Shopify", provider: "shopify", external_domain: shop, shopify_oauth: true)
    sign_in
    expect(Connections::ShopifyOauth).not_to receive(:authorization_url)
    expect(Connections::ShopifyApi).not_to receive(:new)
    get "/admin/shopify", params: { shop: shop, store_id: other.id }
    expect(response).to have_http_status(:ok)
    expect(document.at_css("a[href='/admin/store_connections/#{own.id}']")).to be_present
    expect(document.at_css("a[href='/admin/store_connections/#{foreign.id}']")).to be_nil
    expect(response.body).not_to include(foreign.name)
  end

  it "renders localized app home and prefilled setup in French, English and Arabic" do
    sign_in
    %w[fr en ar].each do |locale|
      get "/admin/shopify", params: { shop: shop, locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(document.at_css(".translation_missing")).to be_nil
      link = document.css("a").find { |node| node["href"].include?("/admin/store_connections/new?") }
      expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)).to include("provider" => "shopify", "shop" => shop)
      get link["href"]
      expect(response).to have_http_status(:ok)
      expect(document.at_css("input[name='store_connection[external_domain]']")["value"]).to eq(shop)
    end
  end

  it "discards malformed domain hints and arbitrary return URLs" do
    [ "https://evil.example", "shop.myshopify.com.evil.example", "//evil.example", { domain: shop } ].each do |hint|
      get "/admin/shopify", params: { shop: hint, return_to: "https://evil.example" }
      expect(response).to redirect_to("/admin/login")
    end
    sign_in
    expect(response).to redirect_to("/admin/shopify")
    get "/admin/store_connections/new", params: { provider: "shopify", shop: "https://evil.example" }
    expect(response).to have_http_status(:ok)
    expect(document.at_css("input[name='store_connection[external_domain]']")["value"]).to be_nil
  end

  it "requires a workspace for platform-only administrators" do
    root = User.create!(email: "app-platform-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(root)
    get "/admin/shopify", params: { shop: shop }
    expect(response).to have_http_status(:not_found)
  end

  it "requires subscription access and confines confirmation agents" do
    sign_in
    store.update!(subscription_required: true, billing_status: "past_due")
    get "/admin/shopify", params: { shop: shop }
    expect(response).to redirect_to("/admin/subscription")
    agent = store.users.create!(email: "app-agent-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent")
    sign_in(agent)
    get "/admin/shopify", params: { shop: shop }
    expect(response).to redirect_to("/admin/confirmations/home")
  end
end
