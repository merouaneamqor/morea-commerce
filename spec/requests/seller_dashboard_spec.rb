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
    document.css("aside nav ul a").reject { |link| link["data-subnav-item"].present? && link["data-subnav-item"] != "queue" }.map { |link| link["href"] }   # the pages inside Centre d'appels are checked in call_center_menu_spec
  end

  def owner_menu_links
    %w[/dashboard /commandes /confirmation /clients /livraison /produits /themes /publicites /pixels /comptabilite /equipe /integrations /boutique]
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
    expect(menu_links).to eq(%w[/dashboard /commandes /confirmation /clients /livraison /produits /themes /publicites /comptabilite /equipe /integrations /boutique])
    expect(document.css("aside nav ul li span").map(&:text).join).to include("Publicités")
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).to include(a_string_including("Comptabilité"))
    expect(document.css("aside nav ul li").map { |li| li.text.squish }).not_to include(a_string_matching(/\bProfit\b/))
    expect(document.at_css("h1").text).to include("Bonjour, Salma")
    expect(response.body).to include("Boutique #{suffix}", "Plan Starter")
    expect(document.css("[data-kpis=row1] [data-kpi]").map { |tile| tile.at_css("p").text.squish }).to eq([ "Chiffre d'affaires", "Commandes", "En attente de confirmation", "En cours de livraison", "Annulées", "Refusées" ])
    expect(document.css("[data-kpis=row2] [data-kpi]").map { |tile| tile.at_css("p").text.squish }).to eq([ "Taux de confirmation", "Taux de livraison", "Taux de retour" ])
  end

  it "offers a collapsible menu: a desktop toggle, every label hideable, a tooltip with each name, and the choice restored before paint" do
    sign_in(owner)
    get "/dashboard", params: { locale: "fr" }

    aside = document.at_css("aside")
    toggle = aside.at_css("[data-sidebar-toggle]")
    expect(toggle["aria-expanded"]).to eq("true")
    expect(toggle["class"]).to include("hidden", "lg:grid")                                   # desktop only
    expect([ toggle["data-label-collapse"], toggle["data-label-expand"] ]).to eq([ "Réduire le menu", "Agrandir le menu" ])
    links = aside.css("nav ul li a")
    expect(links).not_to be_empty
    expect(links.map { |link| link.at_css("[data-label]")&.text&.squish }).to eq(links.map { |link| link["title"] })
    expect(aside.css("[data-label]").map { |label| label.text.squish }).to include("Paramètres", "Se déconnecter", "Tableau de bord")
    expect(aside.at_css("[data-collapse-hide]")).to be_present                                # the wordmark and the store card go when collapsed
    expect(response.body).to include('localStorage.getItem("sellerSidebar") === "collapsed"')  # restored before the first paint
    expect(document.at_css("[data-seller-drawer] [data-sidebar-toggle]")["class"]).to include("hidden")

    # A tighter list, so it fits without scrolling; it still scrolls (with a hidden thin bar) only if it ever overflows.
    nav = aside.at_css("nav[data-sidebar-nav]")
    expect(nav["class"]).to include("overflow-y-auto", "p-2.5")
    expect(nav.at_css("ul")["class"]).to include("space-y-0.5")
    expect(links.reject { |link| link["data-subnav-item"] }.map { |link| link["class"][/py-[\d.]+/] }.uniq).to eq([ "py-2" ])
  end

  it "no longer shows the financial cards: they moved to Comptabilité" do
    sign_in(owner)
    customer = store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test")
    store.orders.create!(customer: customer, number: "MONEY-#{suffix}", status: "delivered", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", total_cents: 25_000, delivered_at: 1.hour.ago)
    get "/dashboard", params: { locale: "fr" }
    # Revenue and average basket are back on the dashboard by request, read from AccountingStats; profit stays on Comptabilité.
    expect(response.body).not_to include("Profit net", "Ventes livrées vs publicité", "Profit par produit")
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

  it "limits a confirmation agent to their dashboard, call center and billing, and keeps them off the store dashboard" do
    agent = store.users.create!(email: "agent-#{suffix}@example.test", password: password, confirmation_role: "agent")
    sign_in(agent)
    get "/dashboard"
    expect(response).to redirect_to(%r{/admin/my_stats})
    get home_admin_confirmations_path
    expect(response).to have_http_status(:ok)
    expect(menu_links).to eq(%w[/mes-statistiques /confirmation /facturation])
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
