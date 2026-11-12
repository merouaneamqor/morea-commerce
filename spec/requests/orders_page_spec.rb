require "rails_helper"
require "nokogiri"

RSpec.describe "Orders page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "op-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:other_agent) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:tracksuit) { store.products.create!(name: "Tracksuit", price_cents: 20_000, status: "active") }
  let(:cap) { store.products.create!(name: "Cap", price_cents: 5_000, status: "active") }

  BIDI = [ 0x2066, 0x2069 ].map { |code| code.chr(Encoding::UTF_8) }.join.freeze

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document = Nokogiri::HTML(response.body)
  def card(key) = document.at_css("[data-card=#{key}]")
  def value(key) = card(key)["data-value"].to_i
  def hint(key) = card(key).css("p").last.text.delete(BIDI).squish
  def numbers = document.css("[data-order-row]").map { |row| row["data-order-row"] }

  def make(number, status: "new", disposition: nil, callback_at: nil, days_ago: 0, product: tracksuit, assigned: nil, **columns)
    at = days_ago.days.ago
    record = store.orders.create!(customer: customer, number: number, status: status, currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000, created_at: at, **columns)
    record.order_items.create!(product: product, product_name: product.name, quantity: 1, unit_price_cents: 20_000, total_cents: 20_000)
    OrderConfirmation.create!(store: store, order: record, disposition: disposition || "pending", callback_at: callback_at, assigned_user: assigned, claimed_at: (Time.current if assigned)) if disposition || assigned
    record
  end

  # Created today: 16 orders. Confirmation: pending 2 (one with a scheduled callback), confirmed 11, cancelled 1, wrong 2 (wrong number + blocked).
  # Shipping of the 11 confirmed: to ship 2, in transit 2, scheduled 1, delivered 3, failed 2, returned 1.
  # Eight orders 45 days ago make the previous period: 8.
  before do
    make("P1")
    make("P2", disposition: "callback", callback_at: 1.day.from_now)
    make("W1", disposition: "wrong_number")
    make("W2", disposition: "blocked")
    make("C1", status: "cancelled", cancelled_at: Time.current)
    make("S1", status: "confirmed")
    make("S2", status: "preparing")
    make("T1", status: "picked_up")
    make("T2", status: "in_transit", sendit_code: "SD-1")
    make("L1", status: "postponed")
    make("D1", status: "delivered", delivered_at: Time.current, collected_at: Time.current, collected_cents: 20_000, product: cap)
    make("D2", status: "delivered", delivered_at: Time.current)
    make("D3", status: "delivered", delivered_at: Time.current)
    make("F1", status: "unreachable")
    make("F2", status: "address_issue")
    make("R1", status: "returned", returned_at: Time.current)
    8.times { |i| make("OLD#{i}", days_ago: 45) }
  end

  describe "the figures for an owner" do
    before { sign_in(owner) }

    it "counts the 16 orders of the period once each, by confirmation" do
      get "/admin/orders"

      expect(response).to have_http_status(:ok)
      expect(%w[total pending confirmed cancelled wrong].to_h { |key| [ key, value(key) ] }).to eq("total" => 16, "pending" => 2, "confirmed" => 11, "cancelled" => 1, "wrong" => 2)
      expect(value("pending") + value("confirmed") + value("cancelled") + value("wrong")).to eq(value("total"))   # a partition: 2 + 11 + 1 + 2
    end

    it "counts the 11 confirmed orders once each, by shipping stage" do
      get "/admin/orders"

      expect(%w[to_ship in_transit scheduled delivered failed returned].to_h { |key| [ key, value(key) ] }).to eq(
        "to_ship" => 2, "in_transit" => 2, "scheduled" => 1, "delivered" => 3, "failed" => 2, "returned" => 1
      )
      expect(%w[to_ship in_transit scheduled delivered failed returned].sum { |key| value(key) }).to eq(value("confirmed"))   # 2 + 2 + 1 + 3 + 2 + 1 = 11
    end

    it "prints the shares and the change against the previous period" do
      get "/admin/orders"

      expect(card("total").text.delete(BIDI)).to include("+100 %", "vs période précédente")   # 16 against the 8 orders of 45 days ago
      expect(hint("pending")).to include("13 %")        # 2 / 16 = 12,5
      expect(hint("confirmed")).to include("69 %")      # 11 / 16 = 68,75
      expect(hint("cancelled")).to include("6 %")       # 1 / 16 = 6,25
      expect(hint("in_transit")).to include("18 %")     # 2 / 11
      expect(hint("delivered")).to include("27 %")      # 3 / 11
      expect(hint("returned")).to include("9 %")        # 1 / 11
    end

    it "has no change pill when the previous period had no order" do
      store.orders.where("created_at < ?", 10.days.ago).destroy_all

      get "/admin/orders"

      expect(card("total").text).not_to include("%")
      expect(hint("total")).to eq("sur la période")
    end

    it "leaves archived orders and other stores out" do
      store.orders.find_by!(number: "P1").update!(archived_at: Time.current)
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = foreign.customers.create!(name: "X", phone: "0699999999")
      foreign.orders.create!(customer: stranger, number: "FX1", status: "delivered", currency: "MAD", customer_name: "X", customer_phone: "0699999999",
        customer_city: "Fès", customer_address: "x", subtotal_cents: 100, total_cents: 100)

      get "/admin/orders"

      expect(value("total")).to eq(15)
      expect(value("pending")).to eq(1)
      expect(value("delivered")).to eq(3)
      expect(document.text).not_to include("FX1")
    end

    it "follows the date range: a range with only the old orders counts the 8" do
      get "/admin/orders", params: { from: 46.days.ago.to_date.iso8601, to: 44.days.ago.to_date.iso8601 }

      expect(value("total")).to eq(8)
      expect(value("pending")).to eq(8)
      expect(value("confirmed")).to eq(0)
      expect(numbers.size).to eq(8)
    end
  end

  describe "the table" do
    before { sign_in(owner) }

    it "has as many rows as the Commandes totales card, newest first, with the same range" do
      get "/admin/orders"

      expect(document.at_css("[data-total-count]")["data-total-count"]).to eq("16")
      expect(numbers.size).to eq(16)
      expect(numbers).not_to include("OLD0")
    end

    it "prints a confirmation and a shipping state on each row, from the rules of the cards" do
      get "/admin/orders"

      rows = document.css("[data-order-row]").to_h { |row| [ row["data-order-row"], [ row.at_css("[data-confirmation]")["data-confirmation"], row.at_css("[data-shipping]")["data-shipping"] ] ] }
      expect(rows).to include(
        "P1" => %w[pending none], "P2" => %w[planned none], "W1" => %w[wrong none], "W2" => %w[blocked none], "C1" => %w[cancelled none],
        "S1" => %w[confirmed to_ship], "S2" => %w[confirmed to_ship], "T1" => %w[confirmed in_transit], "T2" => %w[confirmed in_transit], "L1" => %w[confirmed scheduled],
        "D1" => %w[confirmed delivered], "F1" => %w[confirmed failed], "F2" => %w[confirmed failed], "R1" => %w[confirmed returned]
      )
    end

    it "opens the rows behind each card: the filter and the card give the same count" do
      { "pending" => 2, "planned" => 1, "confirmed" => 11, "cancelled" => 1, "wrong" => 2 }.each do |filter, count|
        get "/admin/orders", params: { confirmation: filter }
        expect(numbers.size).to eq(count), "confirmation=#{filter}"
      end
      { "to_ship" => 2, "in_transit" => 2, "scheduled" => 1, "delivered" => 3, "failed" => 2, "returned" => 1 }.each do |filter, count|
        get "/admin/orders", params: { shipping: filter }
        expect(numbers.size).to eq(count), "shipping=#{filter}"
      end
      get "/admin/orders"
      expect(document.at_css("[data-card=wrong]")["href"]).to include("confirmation=wrong")
      expect(document.at_css("[data-card=delivered]")["href"]).to include("shipping=delivered")
    end

    it "draws the cards like the dashboard ones, and a card opens exactly its list, jumping to it" do
      get "/admin/orders", params: { confirmation: "confirmed" }

      open_card = document.at_css("[data-card=confirmed]")
      expect(open_card["aria-current"]).to eq("true")
      expect(open_card["href"]).not_to include("confirmation=")        # the open card goes back to all the orders
      expect(open_card["href"]).to end_with("#orders-list")
      expect(document.at_css("[data-card=cancelled]")["href"]).to include("confirmation=cancelled").and end_with("#orders-list")
      expect(document.at_css("#orders-list")).to be_present            # the anchor the card jumps to
      expect(document.at_css("[data-list-subtitle]").text).to include("Confirmées")
      expect(numbers.size).to eq(open_card["data-value"].to_i)         # the list is exactly what the card counts: 11

      cards = document.css("[data-overview] [data-card]")
      expect(cards.map { |card| card["class"][/h-\[\d+px\]/] }.uniq).to eq([ "h-[110px]" ])                        # same size as the dashboard cards
      expect(cards.select { |card| card["class"].include?("from-[#f7d9a4]") }.map { |card| card["data-card"] }).to eq([ "total" ])   # the gold card
      expect(document.at_css("[data-overview]").to_html).not_to include("border-s-[3px]")                         # no coloured left edge any more
      expect(cards.reject { |card| card["data-card"] == "total" }.map { |card| card.at_css("p span")["class"] }.uniq).to eq([ "shrink-0 text-[#6e6e73]" ])   # grey icon
    end

    it "filters by payment, company, source, product, missed calls and search" do
      get "/admin/orders", params: { payment: "paid" }
      expect(numbers).to eq([ "D1" ])
      get "/admin/orders", params: { payment: "unpaid" }
      expect(numbers).to contain_exactly("D2", "D3")                      # delivered, cash not collected yet

      get "/admin/orders", params: { company: "sendit" }
      expect(numbers).to eq([ "T2" ])
      get "/admin/orders", params: { company: "none" }
      expect(numbers.size).to eq(15)

      get "/admin/orders", params: { connection_id: "manual" }
      expect(numbers.size).to eq(16)

      get "/admin/orders", params: { product: cap.id }
      expect(numbers).to eq([ "D1" ])

      order = store.orders.find_by!(number: "P1")
      ConfirmationAttempt.create!(store: store, order_confirmation: OrderConfirmation.create!(store: store, order: order), user: owner, outcome: "no_answer")
      get "/admin/orders", params: { missed: "1" }
      expect(numbers).to eq([ "P1" ])

      get "/admin/orders", params: { q: "S2" }
      expect(numbers).to eq([ "S2" ])
      get "/admin/orders", params: { q: "client d1" }
      expect(numbers).to eq([ "D1" ])
    end

    it "filters by the agent holding the order, and by unassigned" do
      OrderConfirmation.where(order: store.orders.where(number: "P1")).delete_all
      OrderConfirmation.create!(store: store, order: store.orders.find_by!(number: "P1"), assigned_user: agent, claimed_at: Time.current)

      get "/admin/orders", params: { agent_id: agent.id }
      expect(numbers).to eq([ "P1" ])
      get "/admin/orders", params: { agent_id: "none" }
      expect(numbers.size).to eq(15)
    end

    it "refuses to filter on another store's connection or agent" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = foreign.users.create!(name: "S", email: "s-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")

      get "/admin/orders", params: { agent_id: stranger.id }
      expect(response).to have_http_status(:not_found)
      get "/admin/orders", params: { connection_id: foreign.store_connections.create!(provider: "woocommerce", name: "Foreign shop", external_domain: "foreign.example.test", webhook_secret: "synthetic-webhook-secret").id }
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the older links working on every date: ?status=in_transit shows all dates, with a note" do
      make("OLDT", status: "in_transit", days_ago: 45)

      get "/admin/orders", params: { status: "in_transit" }

      expect(numbers).to contain_exactly("T2", "OLDT")
      expect(document.at_css("[data-all-dates]")).to be_present
      get "/admin/orders", params: { status: "in_transit", from: 3.days.ago.to_date.iso8601, to: Date.current.iso8601 }
      expect(numbers).to eq([ "T2" ])
      expect(document.at_css("[data-all-dates]")).to be_nil
    end

    it "applies the filters by itself: no Filtrer, Réinitialiser, Archivées, Appels manqués or Clients button, every control submits the form" do
      get "/admin/orders"

      form = document.at_css("form[data-orders-filters]")
      expect(form["data-controller"]).to eq("auto-submit")
      expect(form.css("input[type=submit], button[type=submit]")).to be_empty
      expect(form.css("a")).to be_empty                                  # no reset, archive or customers link
      expect(form.at_css("input[name=missed]")).to be_nil
      selects = form.css("select")
      expect(selects.map { |select| select["name"] }).to eq(%w[confirmation shipping payment company agent_id connection_id product])
      expect(selects.map { |select| select["data-action"] }.uniq).to eq([ "auto-submit#submit" ])   # a choice applies at once, "all" is the way back
      expect(form.at_css("input[name=q]")["data-action"]).to eq("input->auto-submit#debounce")        # the search waits for a pause in typing
      expect(document.text).not_to include("Réinitialiser", "Archivées", "Appels manqués")
    end

    it "still honours the older ?missed=1 and ?status=archived links, which are no longer buttons" do
      order = store.orders.find_by!(number: "P1")
      ConfirmationAttempt.create!(store: store, order_confirmation: OrderConfirmation.create!(store: store, order: order), user: owner, outcome: "no_answer")
      store.orders.find_by!(number: "P2").update!(archived_at: Time.current)

      get "/admin/orders", params: { missed: "1" }
      expect(numbers).to eq([ "P1" ])
      get "/admin/orders", params: { status: "archived" }
      expect(numbers).to eq([ "P2" ])
    end

    it "pages by 25" do
      12.times { |i| make("MORE#{i}") }

      get "/admin/orders"
      expect(document.at_css("[data-total-count]")["data-total-count"]).to eq("28")
      expect(numbers.size).to eq(25)
      get "/admin/orders", params: { page: 2 }
      expect(numbers.size).to eq(3)
    end
  end

  describe "an agent" do
    before { sign_in(agent) }

    it "gets the figures of what she may see: her orders and the unassigned ones, never another agent's" do
      OrderConfirmation.where(order: store.orders.where(number: "P1")).delete_all
      OrderConfirmation.create!(store: store, order: store.orders.find_by!(number: "P1"), assigned_user: other_agent, claimed_at: Time.current)

      get "/admin/orders"

      expect(value("total")).to eq(15)       # P1 is held by another agent
      expect(value("pending")).to eq(1)
      expect(numbers).not_to include("P1")
      expect(document.at_css("select[name=agent_id]")).to be_nil
      expect(document.at_css("select[name=company]")).to be_nil
      expect(document.text).not_to include("Nouvelle commande")
      expect(document.css("[data-order-actions] a[href$='/edit']")).to be_empty
    end
  end

  it "renders in English and Arabic without a missing translation" do
    sign_in(owner)
    %w[en ar].each do |locale|
      get "/admin/orders", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
    end
  end
end
