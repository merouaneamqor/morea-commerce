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
      chips = cards.reject { |card| card["data-card"] == "total" }.map { |card| card.at_css("p span")["class"] }
      expect(chips).to all(include("grid size-6 shrink-0 place-items-center rounded-lg bg-[#"))   # only the symbol is coloured
    end

    it "filters by payment, company, source, product, missed calls and search" do
      get "/admin/orders", params: { payment: "paid" }
      expect(numbers).to eq([ "D1" ])
      get "/admin/orders", params: { payment: "unpaid" }
      expect(numbers).to contain_exactly("D2", "D3")                      # delivered, cash not collected yet

      store.delivery_accounts.create!(provider: "sendit", name: "Sendit principal", connected_at: Time.current)   # the company filter exists only for a connected company
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

    describe "the delivery company filter" do
      def company_select = document.at_css("select[name=company]")

      it "does not exist while no company is connected through its API" do
        store.delivery_accounts.create!(provider: "ozon", name: "Ozon not connected yet")                                # an account with no connection
        store.delivery_accounts.create!(provider: "ameex", name: "Ameex off", connected_at: Time.current, is_active: false)  # connected once, now inactive

        get "/admin/orders"

        expect(company_select).to be_nil
        get "/admin/orders", params: { company: "sendit" }
        expect(numbers.size).to eq(16)                                   # an unknown company is ignored, nothing is hidden by it
      end

      it "offers exactly the connected companies, plus no company, and never another store's" do
        store.delivery_accounts.create!(provider: "sendit", name: "Sendit principal", connected_at: Time.current)
        store.delivery_accounts.create!(provider: "sendit", name: "Sendit second", connected_at: Time.current)           # twice: listed once
        store.delivery_accounts.create!(provider: "cathedis", name: "Cathedis", connected_at: Time.current)
        store.delivery_accounts.create!(provider: "ozon", name: "Ozon not connected")
        foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
        foreign.delivery_accounts.create!(provider: "ameex", name: "Ameex elsewhere", connected_at: Time.current)

        get "/admin/orders"

        options = company_select.css("option").map { |option| [ option.text.squish, option["value"] ] }
        expect(options).to eq([ [ I18n.t("orders_page.filters.all_companies"), "" ], [ "Cathedis", "cathedis" ], [ "Sendit", "sendit" ], [ I18n.t("orders_page.filters.no_company"), "none" ] ])
      end

      it "is not offered to an agent, and a company that is not connected cannot be forced through the URL" do
        store.delivery_accounts.create!(provider: "sendit", name: "Sendit principal", connected_at: Time.current)
        sign_in(agent)
        get "/admin/orders"
        expect(company_select).to be_nil

        sign_in(owner)
        get "/admin/orders", params: { company: "ozon" }                  # not connected: ignored
        expect(numbers.size).to eq(16)
        get "/admin/orders", params: { company: "none" }
        expect(numbers.size).to eq(15)                                    # everything but the Sendit parcel T2
      end
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
      expect(selects.map { |select| select["name"] }).to eq(%w[agent_id product connection_id])   # in this order; the company filter appears only once a company is connected; the cards cover confirmation and shipping
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

  describe "the new order window" do
    before { sign_in(owner) }

    it "opens from the Orders page inside a frame, falling back to the full page without scripts" do
      get "/admin/orders"

      link = document.at_css("a[href='/admin/orders/new']")
      expect(link["data-turbo-frame"]).to eq("order-modal")
      expect(document.at_css("turbo-frame#order-modal")).to be_present
    end

    it "answers the frame with the glass window: customer, product, delivery, fees and summary, in French" do
      get "/admin/orders/new", headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-seller-shell")                       # the frame answer carries no layout
      dialog = document.at_css("turbo-frame#order-modal [data-order-modal-panel][role=dialog]")
      expect(dialog).to be_present
      expect(dialog.at_css("#order-modal-title").text.squish).to include(I18n.t("orders_modal.title"))
      expect(dialog.text).to include(I18n.t("orders_modal.subtitle"), I18n.t("orders_modal.customer"), I18n.t("orders_modal.product"), I18n.t("orders_modal.delivery"), I18n.t("orders_modal.fees"))
      expect(dialog.css("[data-section]").map { |section| section["data-section"] }).to eq(%w[customer delivery summary items fees])
      expect(dialog.css("input[name='order[name]'], input[name='order[phone]'], input[name='order[second_phone]'], input[name='order[address]']").map { |input| input["name"] })
        .to eq(%w[order[name] order[phone] order[second_phone] order[address]])
      expect(dialog.css("input[name='order[name]'][required], input[name='order[phone]'][required]").size).to eq(2)           # the two required stars
      expect(dialog.at_css("[data-order-composer-target=variant]")["disabled"]).to be_present                                 # enabled once a product with variants is picked
      expect(dialog.at_css("[data-order-composer-target=price]")["readonly"]).to be_present
      expect(dialog.at_css("[data-order-composer-target=addButton]")["disabled"]).to be_present                               # nothing picked yet
      expect(dialog.at_css("[data-unlisted]")).to be_present                                                                  # "Produit non listé ? Ajouter manuellement"
      expect(dialog.at_css("input[name='order[scheduled_for]'][type=datetime-local]")).to be_present
      expect(dialog.at_css("textarea[name='order[notes]']")).to be_present
      expect(dialog.at_css("input[name='order[shipping_excluded]'][type=checkbox]")).to be_present                           # the "Exclus" switch
      expect(dialog.at_css("input[name='order[advance_dh]']")).to be_present
      expect(dialog.at_css("select[name='order[agent_id]']")).to be_present
      expect(dialog.css("[data-order-totals] dd").map { |cell| cell["data-order-composer-target"] }).to eq(%w[subtotal shippingText grandTotal advanceText toCollect])
      expect(dialog.at_css("[data-action='order-modal#close']")).to be_present
      expect(dialog.at_css("form")["data-controller"]).to eq("order-composer checkout-city delivery-company")
    end

    it "offers a delivery company only when the store is connected to one, never one that is not connected" do
      get "/admin/orders/new", headers: { "Turbo-Frame" => "order-modal" }
      expect(document.at_css("select[name='order[delivery_provider]']")).to be_nil
      expect(document.at_css("[data-no-company] a")["href"]).to end_with("/integrations#delivery")

      store.delivery_accounts.create!(provider: "ozon", name: "Ozon not connected")
      store.delivery_accounts.create!(provider: "sendit", name: "Sendit", connected_at: Time.current)
      get "/admin/orders/new", headers: { "Turbo-Frame" => "order-modal" }
      options = document.css("select[name='order[delivery_provider]'] option").map { |option| [ option.text.squish, option["value"] ] }
      expect(options).to eq([ [ I18n.t("orders_modal.company_placeholder"), "" ], [ "Sendit", "sendit" ] ])
    end

    it "stays a normal page when it is not opened in a frame" do
      get "/admin/orders/new"

      expect(document.at_css("h1").text.squish).to eq("Create order")
      expect(document.at_css("[data-order-modal]")).to be_nil
      expect(document.at_css("[data-seller-shell]")).to be_present
    end

    it "keeps the window open, with the message, when the order is refused" do
      post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", city: "Fès", address: "Rue 1" } }, headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("turbo-frame#order-modal [data-order-modal-panel]")).to be_present
      expect(response.body).to include("Add at least one product.")
      expect(store.orders.where(number: nil).count).to eq(0)
    end

    it "answers a created order with a redirect to its page (the browser leaves the window for it)" do
      expect do
        post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", city: "Fès", address: "Rue 1", shipping_dh: 30, lines: [ { product_id: tracksuit.id, quantity: 2 } ] } },
                              headers: { "Turbo-Frame" => "order-modal" }
      end.to change { store.orders.count }.by(1)

      expect(response).to redirect_to("/admin/orders/#{store.orders.order(:id).last.id}")
      expect(store.orders.order(:id).last.total_cents).to eq(43_000)                    # 2 x 200,00 + 30,00 shipping
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
