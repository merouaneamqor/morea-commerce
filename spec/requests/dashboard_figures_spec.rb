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

  it "reads revenue from AccountingStats, the same figure as Comptabilité, and no longer prints the average basket card" do
    get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

    accounting = AccountingStats.new(store: store, range: DateRange.from_params({ from: Date.current.iso8601, to: Date.current.iso8601 }))
    revenue = accounting.totals.revenue / 100.0
    expect(revenue).to be_positive
    expect(kpi("revenue")).to include(ActionController::Base.helpers.number_with_precision(revenue, precision: 2, strip_insignificant_zeros: true, delimiter: " ", separator: ",").delete("⁦⁩"))
    expect(document.at_css("[data-kpi=average_basket]")).to be_nil
  end

  it "lays the cards out as six figures then three rates, in the asked order" do
    get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

    expect(document.css("[data-kpis=row1] [data-kpi]").map { |card| card["data-kpi"] }).to eq(%w[revenue orders en-attente-de-confirmation en-cours-de-livraison annulees refusees])
    expect(document.css("[data-kpis=row2] [data-kpi]").map { |card| card["data-kpi"] }).to eq(%w[confirmation_rate taux-de-livraison taux-de-retour])
  end

  it "draws the cards like Comptabilité: gold revenue card, white bordered cards with a small grey icon, no tints" do
    get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

    cards = document.css("[data-kpis] [data-kpi]")
    expect(cards.size).to eq(9)
    expect(cards.map { |card| card["class"][/h-\[\d+px\]/] }.uniq).to eq([ "h-[110px]" ])
    gold, others = cards.partition { |card| card["class"].include?("from-[#f7d9a4]") }
    expect(gold.map { |card| card["data-kpi"] }).to eq([ "revenue" ])
    expect(others).to all(satisfy { |card| card["class"].include?("border border-[#e0e0e5] bg-white") })
    expect(others.map { |card| card.at_css("p span")["class"] }.uniq).to eq([ "shrink-0 text-[#6e6e73]" ])   # the grey icon beside the label
    expect(response.body).not_to match(/bg-\[#(f1faf5|f2f7fd|fff8ea|fef2f3)\]/)                             # the old tints are gone
  end

  it "no longer prints the sentence about orders waiting under the greeting" do
    get "/dashboard", params: { locale: "fr" }

    expect(document.at_css("h1").text).to include("Bonjour")
    expect(response.body).not_to include("attendent une confirmation")
    expect(response.body).not_to include("Aucune commande en attente de confirmation.")
  end

  it "prints the milestone goal in white on the navy bar" do
    get "/dashboard", params: { locale: "fr" }

    goal = document.at_css("[data-milestone-goal]")
    expect(goal["class"]).to include("text-white")
    expect(goal.next_element["class"]).to include("text-white/65")
  end

  describe "the order distribution" do
    def view(key) = document.at_css("[data-distribution-view=#{key}]")
    def segment(key, name) = view(key).at_css("[data-legend=#{name}]")
    def count_of(key, name) = segment(key, name).at_css("[data-segment-count]").text.delete(BIDI_MARKS).squish.to_i

    it "splits the 7 orders by confirmation, adding up to the total" do
      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      expect(view("confirmation")["data-total"]).to eq("7")
      expect(%w[pending confirmed planned cancelled wrong].to_h { |name| [ name, count_of("confirmation", name) ] }).to eq(
        "pending" => 1, "confirmed" => 5, "planned" => 0, "cancelled" => 1, "wrong" => 0    # new / delivered 2 + transit + returned + confirmed / - / cancelled / -
      )
      expect(segment("confirmation", "confirmed").at_css("[data-segment-percent]").text.delete(BIDI_MARKS).squish).to eq("71,4 %")   # 5 of 7, French decimal comma
      expect(view("confirmation").css("circle[data-segment]").map { |circle| circle["data-count"].to_i }.sum).to eq(7)
    end

    it "counts a scheduled callback and a wrong number apart from the pending orders" do
      callback = make_order("new", 1_000)
      OrderConfirmation.create!(store: store, order: callback, disposition: "callback", callback_at: 1.day.from_now)
      bad = make_order("new", 1_000)
      OrderConfirmation.create!(store: store, order: bad, disposition: "wrong_number")
      blocked = make_order("new", 1_000)
      OrderConfirmation.create!(store: store, order: blocked, disposition: "blocked")

      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      expect(view("confirmation")["data-total"]).to eq("10")
      expect(%w[pending planned wrong].map { |name| count_of("confirmation", name) }).to eq([ 1, 1, 2 ])
    end

    it "splits the 5 confirmed orders by where they are on their way" do
      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      expect(view("shipping")["data-total"]).to eq("5")
      expect(%w[to_ship in_transit delivered issue returned].to_h { |name| [ name, count_of("shipping", name) ] }).to eq(
        "to_ship" => 1, "in_transit" => 1, "delivered" => 2, "issue" => 0, "returned" => 1
      )
    end

    it "shows the confirmation view first and the shipping view hidden behind its button" do
      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      expect(view("confirmation").has_attribute?("hidden")).to be(false)
      expect(view("shipping").has_attribute?("hidden")).to be(true)
      expect(document.css("[data-distribution] button[data-key]").map(&:text).map(&:squish)).to eq(%w[Confirmation Expédition])
    end
  end

  describe "the best products" do
    let(:tracksuit) { store.products.create!(name: "Tracksuit", price_cents: 10_000, status: "active") }
    let(:cap) { store.products.create!(name: "Cap", price_cents: 5_000, status: "active") }

    def item(order, product, quantity, total)
      order.order_items.create!(product: product, product_name: product.name, quantity: quantity, unit_price_cents: total / quantity, total_cents: total)
    end

    it "ranks by the value of the delivered items, with orders, pieces and a bar relative to the best" do
      delivered = store.orders.where(status: "delivered").order(:id).to_a
      item(delivered[0], tracksuit, 2, 20_000)
      item(delivered[0], cap, 1, 5_000)
      item(delivered[1], tracksuit, 1, 8_000)
      item(delivered[1], cap, 1, 2_000)
      item(store.orders.find_by!(status: "returned"), cap, 9, 90_000)    # not delivered: left out
      item(store.orders.find_by!(status: "in_transit"), cap, 9, 90_000)

      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      rows = document.css("[data-product-row]")
      expect(rows.map { |row| row.at_css("p.truncate").text.squish }).to eq(%w[Tracksuit Cap])
      expect(rows.map { |row| row.at_css("[data-revenue]")["data-revenue"].to_f }).to eq([ 280.0, 70.0 ])      # 200 + 80, 50 + 20
      expect(rows.first.text.delete(BIDI_MARKS)).to include("2 commandes · 3 pcs")
      expect(rows.last.text.delete(BIDI_MARKS)).to include("2 commandes · 2 pcs")
      expect(rows.last.at_css("div[style*=width]")["style"]).to include("width: 25.0%")                          # 70 / 280
    end

    it "shows the empty message when nothing was delivered with items, and never another store's sales" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = foreign.customers.create!(name: "X", phone: "0699999999")
      order = foreign.orders.create!(customer: stranger, number: "FX1", status: "delivered", currency: "MAD", customer_name: "X", customer_phone: "0699999999",
        customer_city: "Fès", customer_address: "x", subtotal_cents: 9_900, total_cents: 9_900, delivered_at: Time.current)
      order.order_items.create!(product: foreign.products.create!(name: "Secret", price_cents: 9_900, status: "active"), product_name: "Secret", quantity: 1, unit_price_cents: 9_900, total_cents: 9_900)

      get "/dashboard", params: { from: Date.current.iso8601, to: Date.current.iso8601, locale: "fr" }

      expect(document.at_css("[data-top-products]").text).to include("Aucune vente livrée sur la période.")
      expect(response.body).not_to include("Secret")
    end
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
