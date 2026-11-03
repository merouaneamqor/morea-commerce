# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seller integrations page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma", password: password, admin: true) }

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def connect(provider, domain, store: self.store, active: true, **extra)
    store.store_connections.create!({ provider: provider, name: "#{provider} #{domain}", external_domain: domain, token: SecureRandom.hex(16),
      webhook_secret: SecureRandom.hex(16), active: active, external_store_id: (provider == "youcan" ? SecureRandom.uuid : nil) }.merge(extra))
  end

  def cards
    document.css("section").first.css("article")
  end

  it "is served at the seallo URL with the integrations entry highlighted" do
    get "/integrations"
    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to eq("Intégrations API")
    expect(document.at_css("aside nav ul a.font-semibold")["href"]).to eq("/integrations")
    expect(cards.map { |card| card.at_css("h3").text }).to eq(%w[Shopify WooCommerce YouCan])
    expect(cards.map { |card| card.text.include?("Non connectée") }).to all(be(true))
    expect(response.body).to include("/livraison", "Bientôt disponible")
  end

  it "shows which platforms are connected, with the domain, and only the workspace's own connections" do
    connect("woocommerce", "boutique-#{suffix}.example.test")
    connect("youcan", "old-#{suffix}.example.test", active: false)
    other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
    connect("youcan", "foreign-#{suffix}.example.test", store: other)

    get "/integrations"
    expect(cards.map { |card| card.text.include?("Connectée") && !card.text.include?("Non connectée") }).to eq([ false, true, false ])
    expect(cards[1].text).to include("boutique-#{suffix}.example.test")
    expect(response.body).not_to include("foreign-#{suffix}", "old-#{suffix}")
  end

  it "sends each platform's connect button to the existing connect flow" do
    get "/integrations"
    modals = document.css("[data-modal]").to_h { |modal| [ modal["data-modal"], modal.at_css("a")["href"] ] }
    expect(modals).to eq("shopify" => "/admin/seallo/connect", "woocommerce" => "/admin/woocommerce/connect",
      "youcan" => "/admin/store_connections/new?provider=youcan")
    expect(document.css("[data-connect]").map { |button| button["data-connect"] }).to eq(%w[shopify woocommerce youcan])
  end

  it "disconnects a store without deleting its history" do
    connection = connect("woocommerce", "boutique-#{suffix}.example.test")
    get "/integrations"
    form = document.css("form").find { |f| f.at_css("input[name=operation][value=disconnect]") }
    expect(form["action"]).to eq("/admin/store_connections/#{connection.id}")
    patch "/admin/store_connections/#{connection.id}", params: { operation: "disconnect" }
    expect(connection.reload.active).to be(false)
    get "/integrations"
    expect(cards[1].text).to include("Non connectée")
  end

  it "does not let one workspace disconnect another's connection" do
    other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
    foreign = connect("woocommerce", "foreign-#{suffix}.example.test", store: other)
    patch "/admin/store_connections/#{foreign.id}", params: { operation: "disconnect" }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.active).to be(true)
  end

  it "requires authentication" do
    delete "/admin/logout"
    get "/integrations"
    expect(response).to redirect_to(%r{/admin/login})
  end

  %w[fr en ar].each do |locale|
    it "renders in #{locale} without missing translations" do
      get "/integrations", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(response.body).not_to match(/translation missing/i)
    end
  end
end
