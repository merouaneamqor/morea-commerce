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
    expect(response.body).to include("Bientôt disponible")
  end

  describe "delivery companies dialog" do
    def catalog
      JSON.parse(document.at_css("[data-delivery-modal]")["data-catalog"])
    end

    def add_account(**fields)
      post "/livraison/societes", params: { delivery_account: { provider: "ozon", name: "Ozon (WALKFIT)", account_type: "normal", allow_open: "true", is_active: "true" }.merge(fields) }
    end

    it "opens in place from the delivery card instead of leading to the Delivery page" do
      get "/integrations"
      card = document.at_css("[data-delivery-new]")
      expect(card.name).to eq("button")
      expect(card.text).to include("Gérer les sociétés de livraison")
      expect(document.css("main a").map { |link| link["href"] }).not_to include("/livraison", "/admin/delivery")
    end

    it "carries the provider catalogue: 15 providers, regions, countries and the other-company entry" do
      get "/integrations"
      providers = catalog["providers"]
      expect(providers.keys.length).to eq(16)
      expect(providers.except("other").values.count { |p| p["region"] == "africa" }).to eq(14)
      expect(providers.values.count { |p| p["region"] == "america" }).to eq(1)
      expect(providers.values.count { |p| p["countries"].include?("MA") }).to eq(13)
      expect(catalog["regions"]).to eq("africa" => "Afrique", "america" => "Amérique")
      expect(catalog["countries"].keys).to eq(%w[MA TN CR PA])
      expect(providers["sendit"]).to include("name" => "Sendit", "logo" => "/images/partners/sendit.png")
    end

    it "connects a provider with its API keys, keeps them encrypted, and shows it connected on the same page" do
      add_account(api_key: "pub-123", api_secret: "secret-456", pickup_city: "Casablanca", delivery_fee: "25", return_fee: "12.5")
      expect(response).to redirect_to(%r{/integrations})
      account = store.delivery_accounts.sole
      expect(account).to have_attributes(provider: "ozon", name: "Ozon (WALKFIT)", code: "OZO1", pickup_city: "Casablanca", is_active: true)
      expect(account.delivery_fee).to eq(25)
      expect(account.credentials).to eq("api_key" => "pub-123", "api_secret" => "secret-456")
      expect(account.credentials_ciphertext).not_to include("secret-456")
      expect(account.connected_at).to be_present

      follow_redirect!
      expect(response).to have_http_status(:ok)
      row = document.at_css("[data-account='#{account.id}']")
      expect(row.text).to include("Ozon (WALKFIT)", "OZO1", "Connectée")
      expect(response.body).not_to include("secret-456", "pub-123")
    end

    it "numbers the codes per company and supports several accounts at one company" do
      add_account(name: "Ozon 1")
      add_account(name: "Ozon 2")
      add_account(provider: "cathedis", name: "Cathedis")
      expect(store.delivery_accounts.order(:id).pluck(:code)).to eq(%w[OZO1 OZO2 CAT1])
    end

    it "does not feed Sendit's keys from other companies" do
      add_account(api_key: "ozon-pub", api_secret: "ozon-secret")
      expect(store.reload.sendit_configured?).to be(false)
    end

    it "adds another company without API keys in manual mode" do
      add_account(provider: "other", name: "Ma société")
      account = store.delivery_accounts.sole
      expect(account).to have_attributes(provider: "other", code: "AUT1", connected_at: nil)
      expect(account.credentials?).to be(false)
    end

    it "edits an account, keeps the saved keys when the fields are left empty, and can deactivate or delete it" do
      add_account(api_key: "pub-1", api_secret: "sec-1")
      account = store.delivery_accounts.sole
      patch "/livraison/societes/#{account.id}", params: { delivery_account: { name: "Renamed", account_type: "premium", allow_open: "false", is_active: "false", api_key: "", api_secret: "" } }
      expect(response).to redirect_to(%r{/integrations})
      expect(account.reload).to have_attributes(name: "Renamed", account_type: "premium", allow_open: false, is_active: false)
      expect(account.credentials).to eq("api_key" => "pub-1", "api_secret" => "sec-1")
      get "/integrations"
      expect(document.at_css("[data-account='#{account.id}']").text).to include("Non connectée")

      expect { delete "/livraison/societes/#{account.id}" }.to change(DeliveryAccount, :count).by(-1)
      expect(response).to redirect_to(%r{/integrations})
    end

    it "rejects invalid input without creating anything" do
      [ { provider: "nope" }, { account_type: "gold" }, { delivery_fee: "-1" }, { name: "" } ].each do |invalid|
        expect { add_account(**invalid) }.not_to change(DeliveryAccount, :count)
        expect(response).to redirect_to(%r{/integrations})
        expect(flash[:alert]).to be_present
      end
    end

    it "does not let one workspace edit or delete another's account" do
      other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
      foreign = other.delivery_accounts.create!(provider: "ozon", name: "Foreign")
      patch "/livraison/societes/#{foreign.id}", params: { delivery_account: { name: "Hacked" } }
      expect(response).to have_http_status(:not_found)
      expect { delete "/livraison/societes/#{foreign.id}" }.not_to change(DeliveryAccount, :count)
      get "/integrations"
      expect(response.body).not_to include("Foreign")
    end
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
