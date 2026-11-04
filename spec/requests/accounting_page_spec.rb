# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Comptabilité page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false, plan: "starter") }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma Benali", password: password, admin: true) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test") }
  let(:zone) { Time.find_zone!("Africa/Casablanca") }

  around { |example| travel_to(zone.local(2026, 11, 5, 12, 0)) { example.run } }

  def document = Nokogiri::HTML(response.body)
  def clean(text) = text.to_s.delete("⁦⁩").tr(" ", " ").squish

  def sign_in(user, host: "#{store.slug}.#{Store.base_domain}")
    host! host
    post "/admin/login", params: { email: user.email, password: password }
  end

  def order(store: self.store, status:, total:, cost: 0, delivered_at: nil, returned_at: nil, shipped_at: nil, delivery_fee: nil, return_fee: nil, items: nil)
    cust = store.customers.first || store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{SecureRandom.hex(3)}@example.test")
    record = store.orders.create!(customer: cust, number: "A#{SecureRandom.hex(4)}", status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: total, total_cents: total, delivered_at: delivered_at, returned_at: returned_at, shipped_at: shipped_at,
      delivery_fee_cents: delivery_fee, return_fee_cents: return_fee)
    (items || [ [ 1, cost, "Montre", nil ] ]).each do |quantity, unit_cost, name, variant|
      record.order_items.create!(product_name: name, variant_name: variant, quantity: quantity, unit_price_cents: total, total_cents: total, unit_cost_cents: unit_cost)
    end
    record
  end

  # October: one delivered order (250 MAD, cost 100, fee 20) and one returned order (fee 10): net = 250 - 100 - (20 + 10) = 120.
  def october_orders
    order(status: "delivered", total: 25_000, cost: 10_000, delivered_at: zone.local(2026, 10, 10, 12, 0), shipped_at: zone.local(2026, 10, 8, 12, 0), delivery_fee: 2_000)
    order(status: "returned", total: 9_000, cost: 3_000, returned_at: zone.local(2026, 10, 12, 12, 0), shipped_at: zone.local(2026, 10, 9, 12, 0), return_fee: 1_000)
  end

  def value_of(key) = clean(document.at_css("[data-card=#{key}] [data-value]").text)

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/comptabilite"
    expect(response).to redirect_to(%r{/admin/login})
  end

  describe "the menu" do
    it "puts Comptabilité (calculator icon) where Profit was, for the owner" do
      sign_in(owner)
      get "/comptabilite"
      links = document.css("aside nav ul a").map { |link| link["href"] }
      expect(links).to eq(%w[/dashboard /commandes /confirmation /clients /livraison /produits /comptabilite /equipe /integrations])
      entry = document.at_css("aside nav ul a[href='/comptabilite']")
      expect(entry.text.squish).to eq("Comptabilité")
      expect(entry.at_css("svg rect")).to be_present
      expect(entry["class"]).to include("font-semibold")
      expect(document.css("aside nav ul li").map { |li| li.text.squish }.join).not_to match(/\bProfit\b/)
    end

    it "is hidden from confirmation agents, who cannot open the page either" do
      agent = store.users.create!(email: "agent-#{suffix}@example.test", password: password, confirmation_role: "agent")
      sign_in(agent)
      get home_admin_confirmations_path
      expect(document.css("aside nav ul a").map { |link| link["href"] }).not_to include("/comptabilite")
      get "/comptabilite"
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Chiffre d'affaires")
      get "/comptabilite/export", params: { format: "csv" }
      expect(response).not_to have_http_status(:ok)
    end

    it "is translated" do
      sign_in(owner)
      { "en" => "Accounting", "ar" => "المحاسبة" }.each do |locale, word|
        get "/comptabilite", params: { locale: locale }
        expect(document.at_css("aside nav ul a[href='/comptabilite']").text.squish).to eq(word)
      end
    end
  end

  describe "the page" do
    before { october_orders }

    it "shows the header, the five tabs (no Trésorerie), the toggle, the date range picker and the export" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("h1").text.squish).to eq("Comptabilité")
      expect(document.css("[data-tabs] a").map { |tab| tab.text.squish }).to eq([ "Vue d'ensemble", "Compte de résultat", "Créances", "Dettes", "Inventaire" ])
      expect(response.body).not_to include("Trésorerie")
      toggle = document.css("[data-basis-toggle] a")
      expect(toggle.map { |link| link.text.squish }).to eq(%w[Livrées Expédiées])
      expect(toggle.first["aria-current"]).to eq("true")
      picker = document.at_css("[data-controller=date-range-picker]")
      expect(picker["data-date-range-picker"]).to eq("2026-10-01/2026-10-31")
      expect(picker.at_css("[data-date-range-label]").text.squish).to eq("Mois dernier")
      expect(document.at_css("a[data-export]")["href"]).to eq("/comptabilite/export?basis=delivered&from=2026-10-01&to=2026-10-31")
    end

    it "shows the nine figures, calculated by hand, in the right order" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(document.css("[data-cards=first] [data-card]").map { |card| card["data-card"] }).to eq(%w[revenue goods gross_margin delivery net])
      expect(document.css("[data-cards=second] [data-card]").map { |card| card["data-card"] }).to eq(%w[basket ads expenses margin])
      expect(value_of("revenue")).to eq("250 MAD")
      expect(value_of("goods")).to eq("100 MAD")
      expect(value_of("gross_margin")).to eq("150 MAD")
      expect(value_of("delivery")).to eq("30 MAD")      # 20 delivered + 10 return fee
      expect(value_of("net")).to eq("120 MAD")          # 250 - 100 - 30 - 0
      expect(value_of("basket")).to eq("250 MAD")       # 250 / 1 delivered order
      expect(value_of("ads")).to eq("0 MAD")
      expect(value_of("expenses")).to eq("130 MAD")     # 100 + 30 + 0
      expect(value_of("margin")).to eq("48,0 %")        # 120 / 250
      expect(clean(document.at_css("[data-card=delivery]").text)).to include("1 retours inclus")
      expect(clean(document.at_css("[data-card=ads]").text)).to include("Meta + TikTok")
    end

    it "shows the change versus the previous period: Nouveau when it was 0, and a sparkline on every card" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(document.at_css("[data-card=revenue] [data-change]").text.squish).to eq("Nouveau")
      expect(document.css("[data-card] svg polyline").length).to eq(9)

      order(status: "delivered", total: 10_000, cost: 2_000, delivered_at: zone.local(2026, 9, 15, 12, 0), delivery_fee: 1_000)
      get "/comptabilite", params: { month: "2026-10" }
      expect(document.at_css("[data-card=revenue] [data-change]").text.squish).to eq("↗ 150 %") # (250 - 100) / 100
      expect(document.at_css("[data-card=revenue] [data-change]")["data-change"]).to eq("up")
    end

    it "colours a rising cost red and a rising result green" do
      order(status: "delivered", total: 10_000, cost: 2_000, delivered_at: zone.local(2026, 9, 15, 12, 0), delivery_fee: 1_000)
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(document.at_css("[data-card=goods] [data-change]")["class"]).to include("text-[#b4344e]")
      expect(document.at_css("[data-card=gross_margin] [data-change]")["class"]).to include("text-[#2f7a4a]")
    end

    it "splits each 100 MAD: four parts adding up to exactly 100, and links the three small cards to their tabs" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      # revenue 250: goods 100 -> 40,0 ; delivery 30 -> 12,0 ; ads 0 ; profit 120 -> 48,0
      shares = document.css("[data-part]").to_h { |part| [ part["data-part"], clean(part.at_css("p.text-2xl").text) ] }
      expect(shares).to eq("goods" => "40,0 MAD", "delivery" => "12,0 MAD", "ads" => "0,0 MAD", "profit" => "48,0 MAD")
      expect(shares.values.sum { |text| text.to_s.delete(" MAD").tr(",", ".").to_f }).to eq(100.0)
      expect(document.css("[data-side-cards] a").map { |link| link["href"] }).to eq(
        %w[receivables debts inventory].map { |tab| "/comptabilite?basis=delivered&from=2026-10-01&preset=last_month&tab=#{tab}&to=2026-10-31" })
      expect(document.css("[data-side-cards] a").map { |link| link["data-side"] }).to eq(%w[receivables debts inventory])
    end

    it "switches to shipped orders" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10", basis: "shipped" }
      expect(document.css("[data-basis-toggle] a").last["aria-current"]).to eq("true")
      expect(value_of("revenue")).to eq("250 MAD")
      order(status: "delivered", total: 40_000, cost: 0, shipped_at: zone.local(2026, 10, 20, 12, 0), delivered_at: zone.local(2026, 11, 2, 12, 0), delivery_fee: 0)
      get "/comptabilite", params: { month: "2026-10", basis: "shipped" }
      expect(value_of("revenue")).to eq("650 MAD")
      get "/comptabilite", params: { month: "2026-10", basis: "delivered" }
      expect(value_of("revenue")).to eq("250 MAD")
    end

    it "falls back to this month for a missing, bad or future range" do
      sign_in(owner)
      [ {}, { month: "garbage" }, { month: "2027-05" }, { month: "2026-13" }, { from: "bad", to: "2026-10-31" }, { from: "2026-11-10", to: "2026-11-20" } ].each do |params|
        get "/comptabilite", params: params
        expect(document.at_css("[data-controller=date-range-picker]")["data-date-range-picker"]).to eq("2026-11-01/2026-11-05"), params.inspect
        expect(document.at_css("[data-date-range-label]").text.squish).to eq("Ce mois")
      end
    end

    it "keeps the other tabs for later" do
      sign_in(owner)
      %w[receivables debts inventory].each do |tab|
        get "/comptabilite", params: { tab: tab, month: "2026-10" }
        expect(document.at_css("[data-tab-later=#{tab}]")).to be_present
        expect(document.at_css("[data-tabs] a[aria-current=page]").text.squish).to eq(I18n.t("accounting.tabs.#{tab}", locale: :fr))
      end
    end

    it "shows only this store's figures" do
      other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
      order(store: other, status: "delivered", total: 999_900, delivered_at: zone.local(2026, 10, 10, 12, 0), delivery_fee: 0)
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(value_of("revenue")).to eq("250 MAD")
    end

    it "says what is missing: costs and fees that were not known" do
      order(status: "delivered", total: 1_000, cost: nil, delivered_at: zone.local(2026, 10, 15, 12, 0), delivery_fee: nil)
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      text = clean(document.at_css("[data-warnings]").text)
      expect(text).to include("1 commandes livrées ont un produit sans coût", "1 commandes livrées sans frais de livraison connus")
    end
  end

  describe "the Compte de résultat tab" do
    def amount(key) = clean(document.at_css("[data-amount=#{key}]").text)

    before do
      order(status: "delivered", total: 150_000, items: [ [ 2, 19_600, "Tracksuit", "M" ], [ 1, 19_600, "Tracksuit", "L" ] ], delivered_at: zone.local(2026, 10, 5, 10, 0), delivery_fee: 2_500)
      order(status: "delivered", total: 60_000, items: [ [ 1, 15_000, "Tracksuit", "M" ] ], delivered_at: zone.local(2026, 10, 6, 10, 0), delivery_fee: 2_500)
      order(status: "delivered", total: 150_000, items: [ [ 5, 15_587, "Basic", nil ] ], delivered_at: zone.local(2026, 10, 7, 10, 0), delivery_fee: 2_500)
      order(status: "returned", total: 9_000, items: [ [ 1, 3_000, "Tracksuit", "M" ] ], returned_at: zone.local(2026, 10, 8, 10, 0), return_fee: 1_500)
      sign_in(owner)
    end

    it "prints the statement with the same figures as the overview, to the centime" do
      get "/comptabilite", params: { tab: "income", month: "2026-10" }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-tabs] a[aria-current=page]").text.squish).to eq("Compte de résultat")
      expect(document.at_css("[data-tab-later]")).to be_nil
      expect(amount("product_sales")).to eq("3 600,00 MAD")
      expect(amount("revenue")).to eq("3 600,00 MAD")
      expect(amount("product_costs")).to eq("1 517,35 MAD")           # 779,35 + 738,00
      expect(amount("goods")).to eq("(1 517,35 MAD)")
      expect(amount("gross_margin")).to eq("2 082,65 MAD")            # 3 600 - 1 517,35
      expect(clean(document.at_css("[data-share=gross]").text)).to eq("57,9 %") # 2 082,65 / 3 600
      expect(amount("ads")).to eq("(0,00 MAD)")
      expect(amount("delivery_delivered")).to eq("75,00 MAD")         # 3 x 25
      expect(amount("delivery_returned")).to eq("15,00 MAD")
      expect(amount("delivery")).to eq("(90,00 MAD)")
      expect(amount("operating")).to eq("(0,00 MAD)")
      expect(amount("net")).to eq("1 992,65 MAD")                     # 3 600 - 1 517,35 - 90 - 0
      expect(clean(document.at_css("[data-share=net]").text)).to eq("55,4 %") # 1 992,65 / 3 600
      expect(clean(document.at_css("[data-block=goods]").text)).to include("Basé sur les commandes livrées")
    end

    it "lists the cost of goods by product with its quantity and unit cost, and the variants in a detail" do
      get "/comptabilite", params: { tab: "income", month: "2026-10" }
      basic = document.at_css("[data-product=Basic]")
      expect(clean(basic.text)).to include("5 × 155,87 MAD", "779,35")
      expect(basic.at_css("details")).to be_nil # one variant without a name: nothing to detail
      tracksuit = document.at_css("[data-product=Tracksuit]")
      expect(clean(tracksuit.text)).to include("4 unités", "738,00", "Voir le détail (2 variantes)") # the cost changed: no single unit cost
      expect(tracksuit.css("details li[data-variant]").map { |li| clean(li.text) }).to eq([ "M 3 unités 542,00", "L 1 × 196,00 MAD 196,00" ])
      shown = document.css("[data-amount=product]").sum { |node| (BigDecimal(clean(node.text).delete(" ").tr(",", ".")) * 100).to_i }
      expect(shown).to eq(151_735)
    end

    it "follows the basis and the month" do
      get "/comptabilite", params: { tab: "income", month: "2026-10", basis: "shipped" }
      expect(clean(document.at_css("[data-block=goods]").text)).to include("Basé sur les commandes expédiées")
      get "/comptabilite", params: { tab: "income", month: "2026-09" }
      expect(amount("revenue")).to eq("0,00 MAD")
      expect(document.at_css("[data-income]").text).to include("Aucune commande livrée ou retournée")
    end

    it "shows a net loss in red when the month loses money" do
      order(status: "delivered", total: 1_000, items: [ [ 1, 900_000, "Cher", nil ] ], delivered_at: zone.local(2026, 10, 9, 10, 0), delivery_fee: 0)
      get "/comptabilite", params: { tab: "income", month: "2026-10" }
      block = document.at_css("[data-block=net]")
      expect(clean(block.text)).to include("Perte nette")
      expect(block["class"]).to include("bg-[#fdeff1]")
      expect(amount("net")).to start_with("−")
    end

    %w[en ar].each do |locale|
      it "renders in #{locale} without missing translations" do
        get "/comptabilite", params: { tab: "income", month: "2026-10", locale: locale }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to match(/translation missing/i)
        expect(document.at_css("[data-income] h2").text.squish).to eq(I18n.t("accounting.income.title", locale: locale))
      end
    end
  end

  describe "a store with no orders" do
    it "shows dashes where a division is impossible, not zeros or errors" do
      sign_in(owner)
      get "/comptabilite", params: { month: "2026-10" }
      expect(response).to have_http_status(:ok)
      expect(value_of("revenue")).to eq("0 MAD")
      expect(value_of("basket")).to eq("—")
      expect(value_of("margin")).to eq("—")
      expect(document.at_css("[data-split]").text.squish).to include("Aucun chiffre d'affaires")
      expect(document.at_css("[data-card=revenue] [data-change]").text.squish).to eq("—")
      expect(document.at_css("[data-warnings]")).to be_nil
    end
  end

  describe "the export" do
    before { october_orders }

    it "is a CSV whose totals are the sum of its rows and match the cards" do
      sign_in(owner)
      get "/comptabilite/export", params: { month: "2026-10", format: "csv" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("comptabilite-2026-10-01-2026-10-31-delivered.csv")
      rows = CSV.parse(response.body.delete_prefix("﻿"), headers: true)
      lines = rows.reject { |row| row["date"].match?(/\A[A-Z_]+\z/) }
      total = rows.find { |row| row["date"] == "TOTAL" }
      cents = ->(text) { (BigDecimal(text) * 100).to_i }
      %w[revenue cost_of_goods delivery_fees advertising].each do |column|
        expect(lines.sum { |row| cents.(row[column]) }).to eq(cents.(total[column])), column
      end
      expect(total["revenue"]).to eq("250.00")
      expect(total["cost_of_goods"]).to eq("100.00")
      expect(total["delivery_fees"]).to eq("30.00")
      expect(rows.find { |row| row["date"] == "BENEFICE_NET" }["revenue"]).to eq("120.00")
      expect(rows.find { |row| row["date"] == "MARGE_BRUTE" }["revenue"]).to eq("150.00")
      expect(lines.map { |row| row["type"] }).to match_array(%w[livraison retour])
      expect(lines.find { |row| row["type"] == "retour" }.to_h).to include("revenue" => "0.00", "cost_of_goods" => "0.00", "delivery_fees" => "10.00")
    end

    it "follows the same range and basis as the page" do
      sign_in(owner)
      get "/comptabilite/export", params: { month: "2026-10", basis: "shipped", format: "csv" }
      expect(response.headers["Content-Disposition"]).to include("comptabilite-2026-10-01-2026-10-31-shipped.csv")
    end
  end

  %w[fr en ar].each do |locale|
    it "renders in #{locale} without missing translations" do
      october_orders
      sign_in(owner)
      get "/comptabilite", params: { locale: locale, month: "2026-10" }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(response.body).not_to match(/translation missing/i)
      expect(document.at_css("h1").text.squish).to eq(I18n.t("accounting.title", locale: locale))
    end
  end
end
