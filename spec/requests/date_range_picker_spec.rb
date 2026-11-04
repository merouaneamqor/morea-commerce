# frozen_string_literal: true

require "rails_helper"

# The shared date range picker and what it does to the pages: the component itself (presets, settings handed to the
# script, languages), the way each page reads ?from=&to=, and how the last choice is remembered.
# The clicking inside the calendar is script: it is checked in a real browser, not here.
RSpec.describe "Date range picker", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false, plan: "starter") }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma Benali", password: password, admin: true) }
  let(:zone) { Time.find_zone!("Africa/Casablanca") }
  let(:today) { Date.new(2026, 11, 5) }

  around { |example| travel_to(zone.local(2026, 11, 5, 12, 0)) { example.run } }

  def document = Nokogiri::HTML(response.body)
  def clean(text) = text.to_s.delete("⁦⁩").tr(" ", " ").squish
  def picker = document.at_css("[data-controller=date-range-picker]")
  def config = JSON.parse(picker["data-date-range-picker-config-value"])
  def label = clean(picker.at_css("[data-date-range-label]").text)
  def range_of_page = picker["data-date-range-picker"]

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def customer = store.customers.first || store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{SecureRandom.hex(3)}@example.test")

  def order(status: "new", total: 10_000, created_at: zone.local(2026, 11, 1, 10, 0), delivered_at: nil, delivery_fee: 0, cost: 0)
    record = store.orders.create!(customer: customer, number: "P#{SecureRandom.hex(4)}", status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: total, total_cents: total, created_at: created_at, delivered_at: delivered_at, delivery_fee_cents: delivery_fee)
    record.order_items.create!(product_name: "Montre", quantity: 1, unit_price_cents: total, total_cents: total, unit_cost_cents: cost)
    record
  end

  def revenue = clean(document.at_css("[data-card=revenue] [data-value]").text)
  def orders_tile = clean(document.css("section.grid > div").first.css("p")[1].text)

  describe "the component" do
    before { sign_in }

    it "offers the twelve shortcuts in order, then the custom range" do
      get "/dashboard"
      shortcuts = picker.css("[data-presets] li").map { |item| clean(item.text) }
      expect(shortcuts).to eq([ "Aujourd'hui", "Hier", "3 derniers jours", "7 derniers jours", "30 derniers jours", "Ce mois", "Mois dernier", "Cette année",
                                "T1 (Jan-Mar)", "T2 (Avr-Juin)", "T3 (Juil-Sep)", "T4 (Oct-Déc)", "Plage personnalisée" ])
      expect(picker.at_css("button[data-action='date-range-picker#showCustom']")).to be_present
    end

    it "makes every shortcut a plain link that carries the dates and the name, so it works without scripts" do
      get "/dashboard"
      links = picker.css("[data-presets] a").to_h { |link| [ link["data-preset"], link["href"] ] }
      expect(links["today"]).to eq("/dashboard?from=2026-11-05&preset=today&to=2026-11-05")
      expect(links["yesterday"]).to eq("/dashboard?from=2026-11-04&preset=yesterday&to=2026-11-04")
      expect(links["last_7"]).to eq("/dashboard?from=2026-10-30&preset=last_7&to=2026-11-05")
      expect(links["last_month"]).to eq("/dashboard?from=2026-10-01&preset=last_month&to=2026-10-31")
      expect(links["q3"]).to eq("/dashboard?from=2026-07-01&preset=q3&to=2026-09-30")
      expect(links["q4"]).to eq("/dashboard?from=2026-10-01&preset=q4&to=2026-11-05") # the running quarter, to today
      expect(links["this_year"]).to eq("/dashboard?from=2026-01-01&preset=this_year&to=2026-11-05")
    end

    it "does not offer a quarter that has not started" do
      travel_to(zone.local(2026, 1, 15, 12, 0))
      get "/dashboard"
      expect(picker.css("[data-presets] a").map { |link| link["data-preset"] }).to eq(%w[today yesterday last_3 last_7 last_30 this_month last_month this_year q1])
    end

    it "marks the current range in the list, and the custom entry when it is no shortcut" do
      get "/dashboard", params: { from: "2026-10-01", to: "2026-10-31", preset: "last_month" }
      expect(picker.at_css("a[aria-current=true]")["data-preset"]).to eq("last_month")
      expect(picker.at_css("button[data-action='date-range-picker#showCustom']")["aria-current"]).to eq("false")
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      expect(picker.css("a[aria-current=true]")).to be_empty
      expect(picker.at_css("button[data-action='date-range-picker#showCustom']")["aria-current"]).to eq("true")
    end

    it "shows the shortcut's name on the button, or the dates of a custom range" do
      get "/dashboard", params: { from: "2026-11-01", to: "2026-11-05", preset: "this_month" }
      expect(label).to eq("Ce mois")
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      expect(label).to eq("3 oct. → 15 oct. 2026")
      get "/dashboard", params: { from: "2025-12-30", to: "2026-01-03" }
      expect(label).to eq("30 déc. 2025 → 3 janv. 2026")
      get "/dashboard", params: { from: "2026-10-20", to: "2026-10-20" }
      expect(label).to eq("20 oct. 2026")
    end

    it "keeps the picked shortcut's name when two shortcuts are the same days" do
      travel_to(zone.local(2026, 11, 3, 12, 0))
      get "/dashboard", params: { from: "2026-11-01", to: "2026-11-03", preset: "this_month" }
      expect(label).to eq("Ce mois") # 1 to 3 November is also "3 derniers jours"
      get "/dashboard", params: { from: "2026-11-01", to: "2026-11-03" }
      expect(label).to eq("3 derniers jours")
    end

    it "hands the script today in the store's timezone, the range, Monday-first weekdays and the labels" do
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      expect(config).to include("today" => "2026-11-05", "from" => "2026-10-03", "to" => "2026-10-15", "url" => "/dashboard", "rtl" => false)
      expect(config["weekdays"]).to eq(%w[lu ma me je ve sa di])
      expect(config["months"].first(2)).to eq(%w[Janvier Février])
      expect(config["labels"]).to include("start" => "Date de début", "end" => "Date de fin", "apply" => "Appliquer", "cancel" => "Annuler")
      expect(config["labels"]["daysOne"]).to eq("1 jour")
      expect(config["labels"]["daysOther"]).to eq("%{count} jours")
      expect(config["presets"].map { |preset| preset["key"] }).to eq(%w[today yesterday last_3 last_7 last_30 this_month last_month this_year q1 q2 q3 q4])
      expect(config["presets"].find { |preset| preset["key"] == "last_30" }).to include("from" => "2026-10-07", "to" => "2026-11-05")
    end

    it "gives the script no way to pick a future day: today comes from the server and the next month is capped" do
      get "/dashboard"
      expect(config["today"]).to eq(today.iso8601)
      expect(config["presets"].map { |preset| preset["to"] }.max).to eq(today.iso8601)
    end

    it "has Annuler and Appliquer, the start and end fields and the day count" do
      get "/dashboard"
      expect(picker.at_css("button[data-action='date-range-picker#apply']").text.squish).to eq("Appliquer")
      expect(picker.at_css("button[data-action='date-range-picker#cancel']").text.squish).to eq("Annuler")
      expect(picker.at_css("[data-date-range-picker-target=startField]")).to be_present
      expect(picker.at_css("[data-date-range-picker-target=endField]")).to be_present
      expect(picker.at_css("[data-date-range-picker-target=count]")).to be_present
      expect(picker.at_css("[data-fields]").text).to include("Date de début", "Date de fin")
    end

    it "works on a phone: presets on top, the calendar behind the custom entry, one month at a time (the panel is a bottom sheet)" do
      get "/dashboard"
      panel = picker.at_css("[role=dialog]")
      expect(panel["class"]).to include("fixed", "inset-x-3", "bottom-3", "md:absolute")
      expect(picker.at_css("[data-presets]")["class"]).to include("flex-wrap", "md:flex-col")
      expect(picker.at_css("[data-date-range-picker-target=calendar]")["class"]).to include("hidden", "md:block")
    end

    %w[fr en ar].each do |locale|
      it "renders in #{locale}, in the right direction, without missing translations" do
        get "/dashboard", params: { locale: locale }
        expect(response.body).not_to match(/translation missing/i)
        expect(picker.at_css("[role=dialog]")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
        expect(config["rtl"]).to eq(locale == "ar")
        expect(config["weekdays"].length).to eq(7)
        expect(config["months"].length).to eq(12)
        expect(picker.css("[data-presets] li").length).to eq(13)
        expect(label).to eq(I18n.t("date_range.presets.last_7", locale: locale))
      end
    end

    it "starts the week on Monday in every language" do
      { "fr" => "lu", "en" => "Mo", "ar" => "إث" }.each do |locale, monday|
        get "/dashboard", params: { locale: locale }
        expect(config["weekdays"].first).to eq(monday)
      end
    end

    it "uses a right-to-left arrow between the dates in Arabic" do
      get "/dashboard", params: { locale: "ar", from: "2026-10-03", to: "2026-10-15" }
      expect(label).to include("←")
    end
  end

  describe "a range in the URL, on Comptabilité (every figure)" do
    before do
      sign_in
      order(status: "delivered", total: 10_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 10, 31, 23, 59, 0), delivery_fee: 0)   # last minute of October
      order(status: "delivered", total: 20_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 11, 1, 0, 0, 0), delivery_fee: 0)     # first second of November
      order(status: "delivered", total: 40_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 11, 3, 23, 59, 59), delivery_fee: 0)  # last second of 3 November
      order(status: "delivered", total: 80_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 11, 4, 0, 0, 0), delivery_fee: 0)     # first second of 4 November
      order(status: "delivered", total: 160_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 11, 5, 9, 0, 0), delivery_fee: 0)    # today
      order(status: "delivered", total: 320_000, created_at: zone.local(2026, 10, 1), delivered_at: zone.local(2026, 11, 4, 18, 0, 0), delivery_fee: 0)   # yesterday
    end

    def go(from, to, extra = {}) = get("/comptabilite", params: { from: from, to: to }.merge(extra))

    it "today" do
      go("2026-11-05", "2026-11-05")
      expect(revenue).to eq("1 600 MAD")
    end

    it "yesterday: the whole day, 00:00:00 to 23:59:59" do
      go("2026-11-04", "2026-11-04")
      expect(revenue).to eq("4 000 MAD") # 80 000 at 00:00:00 + 320 000 at 18:00 are 800 + 3 200 = 4 000
    end

    it "last month, ending at 23:59 on the last day and not taking the first second of November" do
      go("2026-10-01", "2026-10-31", preset: "last_month")
      expect(revenue).to eq("100 MAD") # only the order at 23:59 on 31 October
      expect(label).to eq("Mois dernier")
    end

    it "a range across two months" do
      go("2026-10-31", "2026-11-03")
      expect(revenue).to eq("700 MAD") # 100 (31 Oct 23:59) + 200 (1 Nov 00:00:00) + 400 (3 Nov 23:59:59)
      expect(label).to eq("31 oct. → 3 nov. 2026")
    end

    it "start = end: one whole day" do
      go("2026-11-03", "2026-11-03")
      expect(revenue).to eq("400 MAD") # the order at 23:59:59, not the one at 00:00:00 the next day
      expect(label).to eq("3 nov. 2026")
    end

    it "swaps a start that is after the end" do
      go("2026-11-03", "2026-10-31")
      expect(range_of_page).to eq("2026-10-31/2026-11-03")
      expect(revenue).to eq("700 MAD")
    end

    it "cuts an end in the future to today, and ignores a range that starts in the future" do
      go("2026-11-04", "2026-12-25")
      expect(range_of_page).to eq("2026-11-04/2026-11-05")
      expect(revenue).to eq("5 600 MAD") # 800 + 3 200 + 1 600
      go("2026-11-06", "2026-11-30")
      expect(range_of_page).to eq("2026-11-04/2026-11-05") # ignored: the page keeps the last valid choice (a fresh visit gets this month)
    end

    it "compares with the same number of days just before: 4 days against the 4 days before" do
      go("2026-11-01", "2026-11-04")
      # revenue 200 + 400 + 800 + 3 200 = 4 600; previous 28 Oct to 31 Oct: 100 -> (4 600 - 100) / 100 = 4 500 %
      expect(revenue).to eq("4 600 MAD")
      expect(clean(document.at_css("[data-card=revenue] [data-change]").text)).to eq("↗ 4500 %")
    end

    it "says Nouveau when the days just before had nothing" do
      go("2026-10-31", "2026-10-31") # the day before, 30 October, has no delivery
      expect(clean(document.at_css("[data-card=revenue] [data-change]").text)).to eq("Nouveau")
    end

    it "exports exactly the range shown, with the dates in the file name" do
      get "/comptabilite/export", params: { from: "2026-10-31", to: "2026-11-03" }
      expect(response.headers["Content-Disposition"]).to include("comptabilite-2026-10-31-2026-11-03-delivered.csv")
      total = CSV.parse(response.body.delete_prefix("﻿"), headers: true).find { |row| row["date"] == "TOTAL" }
      expect(total["revenue"]).to eq("700.00")
    end

    it "ignores damaged dates instead of failing" do
      [ { from: "x", to: "y" }, { from: "2026-02-30", to: "2026-03-01" }, { from: [ "2026-10-01" ], to: [ "2026-10-31" ] }, { from: "2026-10-01" }, { from: "'; DROP TABLE orders; --", to: "2026-10-31" } ].each do |params|
        get "/comptabilite", params: params
        expect(response).to have_http_status(:ok), params.inspect
        expect(range_of_page).to eq("2026-11-01/2026-11-05"), params.inspect
      end
    end
  end

  describe "a range in the URL, on the dashboard" do
    before do
      sign_in
      order(created_at: zone.local(2026, 10, 31, 23, 59, 0))
      order(created_at: zone.local(2026, 11, 1, 0, 0, 0))
      order(created_at: zone.local(2026, 11, 1, 23, 59, 59))
      order(created_at: zone.local(2026, 11, 2, 0, 0, 0))
      order(created_at: zone.local(2026, 11, 5, 8, 0, 0))
    end

    it "counts the orders of whole store days, the end included" do
      get "/dashboard", params: { from: "2026-11-01", to: "2026-11-01" }
      expect(orders_tile).to eq("2") # 00:00:00 and 23:59:59 on 1 November, not 23:59 on 31 October nor 00:00:00 on 2 November
      get "/dashboard", params: { from: "2026-10-31", to: "2026-11-01" }
      expect(orders_tile).to eq("3")
    end

    it "compares with the same number of days just before" do
      get "/dashboard", params: { from: "2026-11-01", to: "2026-11-02" }
      expect(orders_tile).to eq("3")
      expect(clean(document.css("section.grid > div").first.text)).to include("+200 % vs période précédente") # the 2 days before (30 and 31 October) hold 1 order
    end

    it "opens an older ?period= link and keeps working" do
      get "/dashboard", params: { period: "7d" }
      expect(range_of_page).to eq("2026-10-30/2026-11-05")
      expect(label).to eq("7 derniers jours")
    end
  end

  describe "remembering the last choice" do
    before { sign_in }

    it "uses the last choice when the page is opened again without dates" do
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      get "/dashboard"
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
      expect(label).to eq("3 oct. → 15 oct. 2026")
    end

    it "remembers a shortcut by name, so it moves with the days" do
      get "/dashboard", params: { from: "2026-10-30", to: "2026-11-05", preset: "last_7" }
      travel_to(zone.local(2026, 11, 8, 12, 0))
      get "/dashboard"
      expect(range_of_page).to eq("2026-11-02/2026-11-08")
      expect(label).to eq("7 derniers jours")
    end

    it "lets the URL win over the remembered choice, and remembers the new one" do
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      get "/dashboard", params: { from: "2026-09-01", to: "2026-09-30" }
      expect(range_of_page).to eq("2026-09-01/2026-09-30")
      get "/dashboard"
      expect(range_of_page).to eq("2026-09-01/2026-09-30")
    end

    it "keeps each page's choice apart" do
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      get "/comptabilite"
      expect(range_of_page).to eq("2026-11-01/2026-11-05") # this month, not the dashboard's range
      get "/comptabilite", params: { from: "2026-09-01", to: "2026-09-30" }
      get "/dashboard"
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
    end

    it "ignores a damaged cookie and falls back to the page's default" do
      [ "garbage", "p:forever", "c:2026-11-20:2026-11-25", "c:2026-10-01", "p:last_7;x" ].each do |value|
        cookies[:dr_dashboard] = value
        get "/dashboard"
        expect(response).to have_http_status(:ok), value
        expect(range_of_page).to eq("2026-10-30/2026-11-05"), value
      end
    end

    it "stores the choice for a year, in a cookie the script cannot read" do
      get "/dashboard", params: { from: "2026-10-03", to: "2026-10-15" }
      header = response.headers["Set-Cookie"].to_s
      expect(header).to include("dr_dashboard=c%3A2026-10-03%3A2026-10-15").and match(/httponly/i).and match(/samesite=lax/i)
    end
  end

  describe "on the other pages" do
    before { sign_in }

    it "Livraison: the picker replaces the two date fields and keeps the other filters" do
      get "/admin/delivery", params: { from: "2026-10-03", to: "2026-10-15", status: "delivered", q: "ab" }
      expect(response).to have_http_status(:ok)
      expect(document.css("input[type=date]")).to be_empty
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
      expect(config["extra"]).to eq("status" => "delivered", "q" => "ab")
      expect(document.at_css("input[name=from][value='2026-10-03']")).to be_present
      expect(document.at_css("input[name=to][value='2026-10-15']")).to be_present
    end

    it "Livraison: an older ?start_date=&end_date= link still works, and the default is the last 30 days" do
      get "/admin/delivery", params: { start_date: "2026-10-03", end_date: "2026-10-15" }
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
      cookies.delete("dr_delivery")
      get "/admin/delivery"
      expect(range_of_page).to eq("2026-10-07/2026-11-05")
      expect(label).to eq("30 derniers jours")
    end

    it "Livraison: shows the days really used when the page keeps at most a year" do
      get "/admin/delivery", params: { from: "2024-01-01", to: "2026-11-05" }
      expect(range_of_page).to eq("2025-11-05/2026-11-05")
    end

    it "Publicités: the picker replaces the two date fields and keeps the sort" do
      get "/admin/advertising", params: { from: "2026-10-03", to: "2026-10-15", sort: "profit" }
      expect(response).to have_http_status(:ok)
      expect(document.css("input[type=date][name=start_date], input[type=date][name=end_date]")).to be_empty
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
      expect(config["extra"]).to eq("sort" => "profit")
    end

    it "Publicités: an older ?start_date=&end_date= link still works" do
      get "/admin/advertising", params: { start_date: "2026-10-03", end_date: "2026-10-15" }
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
    end

    it "Mes statistiques: the picker replaces the period links, older ?period= links still work" do
      get "/admin/my_stats", params: { from: "2026-10-03", to: "2026-10-15" }
      expect(response).to have_http_status(:ok)
      expect(document.css("nav.admin-dashboard-period")).to be_empty
      expect(range_of_page).to eq("2026-10-03/2026-10-15")
      cookies.delete("dr_my_stats")
      get "/admin/my_stats", params: { period: "week" }
      expect(range_of_page).to eq("2026-10-30/2026-11-05")
      cookies.delete("dr_my_stats")
      get "/admin/my_stats"
      expect(range_of_page).to eq("2026-11-01/2026-11-05")
      expect(label).to eq("Ce mois")
    end

    it "Mes statistiques: one bar per day of the range, 31 at most" do
      get "/admin/my_stats", params: { from: "2026-07-01", to: "2026-11-05" }
      expect(document.css(".seallo-bars__col").length).to eq(31)
      get "/admin/my_stats", params: { from: "2026-11-01", to: "2026-11-03" }
      expect(document.css(".seallo-bars__col").length).to eq(3)
    end
  end
end
