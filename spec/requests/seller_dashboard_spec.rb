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

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/dashboard"
    expect(response).to redirect_to(%r{/admin/login})
  end

  it "renders the seallo shell and dashboard for the store owner with the ten sidebar entries" do
    sign_in(owner)
    get "/dashboard", params: { locale: "fr" }
    expect(response).to have_http_status(:ok)
    expect(menu_links).to eq(%w[/dashboard /commandes /confirmation /clients /livraison /produits /comptabilite /equipe /integrations])
    expect(document.css("aside nav ul li span").map(&:text).join).to include("Publicités")
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).to include(a_string_including("Comptabilité"))
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).not_to include(a_string_matching(/Profit/))
    expect(document.at_css("h1").text).to include("Bonjour, Salma")
    expect(response.body).to include("Boutique #{suffix}", "Plan · Starter")
    expect(document.css("section.grid > div").first(2).map { |tile| tile.at_css("p").text.squish }).to eq([ "Commandes", "Taux de livraison" ])
  end

  it "no longer shows the financial cards: they moved to Comptabilité" do
    sign_in(owner)
    customer = store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test")
    store.orders.create!(customer: customer, number: "MONEY-#{suffix}", status: "delivered", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", total_cents: 25_000, delivered_at: 1.hour.ago)
    get "/dashboard", params: { locale: "fr" }
    expect(response.body).not_to include("Chiffre d'affaires", "Profit net", "Ventes livrées vs publicité", "Profit par produit", "Panier moyen")
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
    expect(menu_links).to eq(%w[/commandes /confirmation /mes-statistiques])
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

  it "sends the seallo page URLs that are not ported yet to their current page, keeping the query string" do
    host! Store.base_domain
    { "/commandes" => "/admin/orders", "/confirmation" => "/admin/confirmations", "/livraison" => "/admin/delivery",
      "/produits" => "/admin/products", "/equipe" => "/admin/staff", "/mes-statistiques" => "/admin/my_stats" }.each do |from, to|
      get from
      expect(response).to redirect_to("http://#{Store.base_domain}#{to}")
    end
    get "/commandes", params: { status: "new", q: "A1" }
    expect(response).to redirect_to("http://#{Store.base_domain}/admin/orders?status=new&q=A1")
  end
end
