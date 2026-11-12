require "rails_helper"
require "nokogiri"

RSpec.describe "Dashboard figures", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "dash-#{SecureRandom.hex(5)}", name: "Dash", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document = Nokogiri::HTML(response.body)
  BIDI_MARKS = [ 0x2066, 0x2069 ].map { |code| code.chr(Encoding::UTF_8) }.join.freeze

  # The page wraps numbers in direction marks; drop them so the text reads as printed.
  def kpi(key) = document.at_css("[data-kpi=#{key}]").text.delete(BIDI_MARKS).squish
  def make_order(status, total, **columns)
    store.orders.create!(customer: customer, number: "D#{SecureRandom.hex(4).upcase}", status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: total, total_cents: total, **columns)
  end

  # 7 orders today: 2 delivered (300 + 100), 1 in transit (200), 1 new (50), 1 cancelled (70), 1 returned (80), 1 confirmed (90)
  before do
    make_order("delivered", 30_000, delivered_at: Time.current, confirmed_at: Time.current)
    make_order("delivered", 10_000, delivered_at: Time.current, confirmed_at: Time.current)
    make_order("in_transit", 20_000, confirmed_at: Time.current)
    make_order("new", 5_000)
    make_order("cancelled", 7_000, cancelled_at: Time.current)
    make_order("returned", 8_000, returned_at: Time.current, confirmed_at: Time.current)
    make_order("confirmed", 9_000, confirmed_at: Time.current)
    sign_in(owner)
  end

  it "prints every figure from the database, by hand-calculated rules" do
    get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

    expect(response).to have_http_status(:ok)
    expect(kpi("orders")).to include("7")
    expect(kpi("confirmation_rate")).to include("71 %").and include("5 confirmées / 7")   # 5 confirmed (not new, not cancelled) of 7
    expect(kpi("en-attente-de-confirmation")).to include("1").and include("50 MAD")       # 1 new order, 50,00
    expect(kpi("en-cours-de-livraison")).to include("1").and include("200 MAD")           # 1 in transit, 200,00
    expect(kpi("taux-de-livraison")).to include("50 %").and include("2 livrées")           # 2 delivered / 4 shipped (2 + transit + returned)
    expect(kpi("taux-de-retour")).to include("25 %").and include("1 retournées")           # 1 returned / 4 shipped
    expect(kpi("annulees")).to include("1").and include("14 %")                             # 1 of 7
    expect(kpi("refusees")).to include("1")
  end

  it "reads revenue and average basket from AccountingStats, the same figures as Comptabilité" do
    get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

    accounting = AccountingStats.new(store: store, range: DateRange.from_params({ from: Date.current.iso8601, to: Date.current.iso8601 }))
    revenue = accounting.totals.revenue / 100.0
    expect(revenue).to be_positive
    expect(kpi("revenue")).to include(ActionController::Base.helpers.number_with_precision(revenue, precision: 2, strip_insignificant_zeros: true, delimiter: " ", separator: ",").delete("⁦⁩"))
    expect(kpi("average_basket")).to include("sur 2 commandes livrées")
  end

  describe "low stock alert (5 pieces or fewer)" do
    it "lists tracked articles at or below 5, lowest first, with variants by their own stock" do
      store.products.create!(name: "Plenty", price_cents: 1_000, status: "active", track_inventory: true, stock: 6)
      store.products.create!(name: "Gone", price_cents: 1_000, status: "active", track_inventory: true, stock: 0)
      store.products.create!(name: "Five", price_cents: 1_000, status: "active", track_inventory: true, stock: 5)
      store.products.create!(name: "Untracked", price_cents: 1_000, status: "active", track_inventory: false, stock: 1)
      store.products.create!(name: "Draft", price_cents: 1_000, status: "draft", track_inventory: true, stock: 1)
      shirt = store.products.create!(name: "Shirt", price_cents: 1_000, status: "active", track_inventory: true, stock: 100)
      shirt.product_variants.create!(name: "M", sku: "S-M", stock: 3, active: true, price_cents: 1_000)
      shirt.product_variants.create!(name: "L", sku: "S-L", stock: 40, active: true, price_cents: 1_000)

      get "/dashboard", params: { locale: "fr" }

      items = document.css("[data-low-stock-item]").map { |row| [ row.at_css("span.font-medium").text.squish, row.at_css("[data-stock]")["data-stock"].to_i ] }
      expect(items).to eq([ [ "Gone", 0 ], [ "Shirt", 3 ], [ "Five", 5 ] ])
      expect(document.at_css("[data-low-stock-count]").text.squish).to eq("3")
      expect(document.at_css("[data-low-stock]").text).to include("Rupture")
    end

    it "shows the empty state when everything is stocked, and never another store's articles" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      foreign.products.create!(name: "Secret low", price_cents: 1_000, status: "active", track_inventory: true, stock: 1)

      get "/dashboard", params: { locale: "fr" }

      expect(document.at_css("[data-low-stock-count]").text.squish).to eq("0")
      expect(document.at_css("[data-low-stock]").text).to include("Aucun article sous le seuil.")
      expect(response.body).not_to include("Secret low")
    end
  end
end
