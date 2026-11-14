# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seller shell and dashboard", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false, plan: "starter") }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma Benali", password: password, admin: true) }

  def document
    Nokogiri::HTML(response.body)
  end

  def sign_in(user, host: "#{store.slug}.#{Store.base_domain}")
    host! host
    post "/admin/login", params: { email: user.email, password: password }
  end

  def menu_links
    document.css("aside nav ul a").map { |link| link["href"] }
  end

  def owner_menu_links
    %w[/dashboard /commandes /confirmation /admin/confirmations/dashboard /admin/confirmations?filter=all /clients /livraison /produits /themes /publicites /pixels /comptabilite /equipe /integrations]
  end

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/dashboard"
    expect(response).to redirect_to(%r{/admin/login})
  end

  it "renders the seallo shell and dashboard for the store owner with the sidebar entries" do
    sign_in(owner)
    get "/dashboard", params: { locale: "fr" }
    expect(response).to have_http_status(:ok)
    expect(menu_links).to eq(owner_menu_links)
    expect(document.css("aside nav ul a").map(&:text).map(&:squish)).to include("Publicités", "File d'attente", "Analyses")
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).to include(a_string_including("Comptabilité"))
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).not_to include(a_string_matching(/\bProfit\b/))
    expect(document.at_css("h1").text).to include("Bonjour, Salma")
    expect(response.body).to include("Boutique #{suffix}", "Plan Starter")
    expect(document.css("[data-kpis=row1] [data-kpi]").first(2).map { |tile| tile.at_css("p").text.squish }).to eq([ "Chiffre d'affaires", "Commandes" ])
  end

  it "shows revenue on the dashboard while keeping detailed accounting charts on Comptabilité" do
    sign_in(owner)
    customer = store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test")
    store.orders.create!(customer: customer, number: "MONEY-#{suffix}", status: "delivered", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", total_cents: 25_000, delivered_at: 1.hour.ago)
    get "/dashboard", params: { locale: "fr" }
    expect(document.at_css("[data-kpi=revenue]").text).to include("Chiffre d'affaires")
    expect(response.body).not_to include("Profit net", "Ventes livrées vs publicité", "Profit par produit", "Panier moyen")
    expect(document.css("[data-sales-chart]")).to be_empty
  end

  it "shows the store's own figures only" do
    sign_in(owner)
    customer = store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test")
    store.orders.create!(customer: customer, number: "OWN-#{suffix}", status: "delivered", currency: "MAD", customer_name: "Client Visible", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", total_cents: 25_000, delivered_at: 1.hour.ago)
    other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
    stranger = other.customers.create!(name: "Etranger", phone: "0699999999", email: "e-#{suffix}@example.test")
    other.orders.create!(customer: stranger, number: "FOREIGN-#{suffix}", status: "delivered", currency: "MAD", customer_name: "Client Etranger", customer_phone: "0699999999",
      customer_city: "Rabat", customer_address: "Rue 2", total_cents: 99_900, delivered_at: 1.hour.ago)
    get "/dashboard"
    body = response.body.delete("⁦⁩")
    expect(body).to include("OWN-#{suffix}", "250 MAD")
    expect(body).not_to include("FOREIGN-#{suffix}", "999 MAD")
  end

  it "limits a confirmation agent to confirmation, statistics and orders, and keeps them off the dashboard" do
    agent = store.users.create!(email: "agent-#{suffix}@example.test", password: password, confirmation_role: "agent")
    sign_in(agent)
    get "/dashboard"
    expect(response).to redirect_to(%r{/admin/confirmations})
    get home_admin_confirmations_path
    expect(response).to have_http_status(:ok)
    expect(menu_links).to eq(%w[/commandes /confirmation /admin/confirmations/dashboard /mes-statistiques])
    expect(response.body).not_to include("Plan · ")
  end

  it "refuses a session from another workspace" do
    sign_in(owner)
    other = Store.create!(name: "Other", slug: "other-#{suffix}", currency: "MAD", storefront_enabled: false)
    host! "#{other.slug}.#{Store.base_domain}"
    get "/dashboard"
    expect(response).to redirect_to(%r{/admin/login})
  end

  it "serves the dashboard on the shared admin host for a merchant" do
    sign_in(owner, host: Store.base_domain)
    expect(response).to redirect_to(%r{/admin})
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to include("Salma")
  end

  it "opens an older ?period= link on the matching range, and falls back to seven days" do
    sign_in(owner)
    get "/dashboard", params: { period: "30d" }
    expect(document.at_css("[data-date-range-label]").text.squish).to eq("30 derniers jours")
    host! "#{store.slug}.#{Store.base_domain}"
    cookies.delete("dr_dashboard")
    get "/dashboard", params: { period: "bogus" }
    expect(document.at_css("[data-date-range-label]").text.squish).to eq("7 derniers jours")
  end

  %w[fr en ar].each do |locale|
    it "renders in #{locale} with the right direction and no missing translation" do
      sign_in(owner)
      get "/dashboard", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["lang"]).to eq(locale)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(response.body).not_to match(/translation missing/i)
    end
  end

  it "shows the first-run onboarding checklist with actions for a new workspace" do
    sign_in(owner)
    get "/dashboard", params: { locale: "en" }
    panel = document.at_css("[data-controller='onboarding-tour']")
    expect(panel).to be_present
    expect(panel.text).to include("Your next steps", "Connect an existing store", "Add a delivery company", "Receive your first order")
    expect(panel.at_css("a[href='/integrations']")).to be_present
    expect(panel.at_css("a[href='/livraison']")).to be_present
    expect(document.css("[data-onboarding-nav='integrations']")).not_to be_empty
    expect(response.body).not_to match(/translation missing/i)
  end

  it "hides onboarding after the workspace completes setup" do
    store.update!(storefront_enabled: true)
    store.products.create!(name: "Item", slug: "item-#{suffix}", status: "active", price_cents: 1500)
    store.store_connections.create!(
      provider: "woocommerce", name: "Woo #{suffix}", external_domain: "woo-#{suffix}.example.test",
      token: "tok-#{SecureRandom.hex(12)}", webhook_secret: "synthetic-secret-#{SecureRandom.hex(8)}"
    )
    store.delivery_accounts.create!(provider: "other", name: "Courier", is_active: true)
    customer = store.customers.create!(name: "Buyer", phone: "0612345678", email: "buyer-#{suffix}@example.test")
    store.orders.create!(
      customer: customer, number: "READY-#{suffix}", status: "confirmed", currency: "MAD",
      customer_name: "Buyer", customer_phone: "0612345678", customer_city: "Fès",
      customer_address: "Rue 1", total_cents: 2500, subtotal_cents: 2500
    )
    sign_in(owner)
    get "/dashboard", params: { locale: "en" }
    expect(document.at_css("[data-controller='onboarding-tour']")).to be_nil
  end

  it "keeps onboarding scoped to the signed-in workspace" do
    other = Store.create!(name: "Other #{suffix}", slug: "other-onboard-#{suffix}", currency: "MAD", storefront_enabled: false)
    other.delivery_accounts.create!(provider: "other", name: "Foreign courier", is_active: true)
    sign_in(owner)
    get "/dashboard", params: { locale: "en" }
    panel = document.at_css("[data-controller='onboarding-tour']")
    expect(panel["data-onboarding-tour-store-id-value"]).to eq(store.id.to_s)
    expect(panel.text).to include("Add a delivery company")
    expect(panel.at_css("a[href='/livraison']")).to be_present
  end

  it "sends the seallo page URLs that are not ported yet to their current page, keeping the query string" do
    host! Store.base_domain
    { "/commandes" => "/admin/orders", "/confirmation" => "/admin/confirmations/center", "/livraison" => "/admin/delivery",
      "/produits" => "/admin/products", "/equipe" => "/admin/staff", "/mes-statistiques" => "/admin/my_stats" }.each do |from, to|
      get from
      expect(response).to redirect_to("http://#{Store.base_domain}#{to}")
    end
    get "/commandes", params: { status: "new", q: "A1" }
    expect(response).to redirect_to("http://#{Store.base_domain}/admin/orders?status=new&q=A1")
  end
end
