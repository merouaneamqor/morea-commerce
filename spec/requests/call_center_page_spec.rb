require "rails_helper"
require "nokogiri"

RSpec.describe "Call center page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "cc-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 1_000, return_penalty_cents: 5_000) }
  let(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 1_000) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:product) { store.products.create!(name: "Tracksuit", price_cents: 20_000, status: "active") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document = Nokogiri::HTML(response.body)
  def value(key) = document.at_css("[data-card=#{key}] [data-value]").text.squish
  def count(tab) = document.at_css("[data-count=#{tab}]").text.squish.to_i
  def numbers = document.css("[data-order-row]").map { |row| row["data-order-row"] }

  # status/disposition as the desk leaves them; `by` is the agent whose call confirmed or cancelled it
  def order(status: "new", disposition: nil, by: nil, outcome: nil, number: nil, collected: false, assigned: nil, callback_at: nil, name: "Client", phone: nil)
    cust = phone ? store.customers.find_or_create_by!(phone: phone) { |c| c.name = name } : customer
    record = store.orders.create!(customer: cust, number: number || "T#{SecureRandom.hex(3).upcase}", status: "new", currency: "MAD", customer_name: name, customer_phone: cust.phone,
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.order_items.create!(product: product, product_name: "Tracksuit", variant_name: "M", quantity: 1, unit_price_cents: 20_000, total_cents: 20_000)
    confirmation = disposition || assigned || by ? OrderConfirmation.create!(store: store, order: record, disposition: disposition || outcome || "pending", assigned_user: assigned, callback_at: callback_at, claimed_at: (Time.current if assigned)) : nil
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: by, outcome: outcome) if by && outcome
    columns = { status: status }
    columns[:confirmed_at] = Time.current if outcome == "confirmed"
    columns[:delivered_at] = Time.current if status == "delivered"
    columns[:cancelled_at] = Time.current if status == "cancelled"
    columns[:collected_at] = Time.current if collected
    columns[:collected_cents] = 20_000 if collected
    record.update_columns(columns)
    record
  end

  # Saida: 2 delivered (1 collected), 1 in transit, 1 unreachable, 1 postponed, 1 returned, 1 cancelled.
  # Omar: 1 delivered. Queue: 3 pending, 1 callback, 1 blocked, 1 held by Omar.
  before do
    @paid = order(status: "delivered", by: agent, outcome: "confirmed", collected: true, number: "PAID1")
    order(status: "delivered", by: agent, outcome: "confirmed")
    order(status: "in_transit", by: agent, outcome: "confirmed")
    order(status: "unreachable", by: agent, outcome: "confirmed")
    order(status: "postponed", by: agent, outcome: "confirmed")
    @returned = order(status: "returned", by: agent, outcome: "confirmed")
    order(status: "cancelled", by: agent, outcome: "cancelled")
    order(status: "delivered", by: omar, outcome: "confirmed")
    3.times { |i| order(number: "Q#{i + 1}", name: "Queue #{i + 1}", phone: "061111111#{i}") }
    order(disposition: "callback", callback_at: 1.day.from_now, number: "CB1", phone: "0622222221")
    order(disposition: "blocked", number: "BLK1", phone: "0633333331")
    order(assigned: omar, number: "OMAR1", phone: "0644444441")
    AgentDeduction.create!(store: store, user: agent, order: @returned, amount_cents: 5_000)
  end

  describe "an agent" do
    before { sign_in(agent) }

    it "sees her own figures, to the unit" do
      get "/admin/confirmations/center"

      expect(response).to have_http_status(:ok)
      expect(value("assigned")).to eq("7")    # 6 confirmed + 1 cancelled by her
      expect(value("pending")).to eq("3")     # 3 unassigned new orders (the callback, blocked and Omar's are not in her queue)
      expect(value("failed")).to eq("1")
      expect(value("confirmed")).to eq("6")
      expect(value("delivered")).to eq("2")   # Omar's delivered order is not hers
      expect(value("cancelled")).to eq("1")
      expect(value("returned")).to eq("1")
    end

    it "prints her commission from the same source as Team, and the pending deduction" do
      get "/admin/confirmations/center"

      expect(value("paid")).to eq("0,00 MAD").or eq("0 MAD").or match(/\A0([.,]00)? ?MAD\z/)
      expect(value("due")).to match(/\A20([.,]00)? ?MAD\z/)         # 2 delivered x 10,00
      expect(value("deductions")).to match(/\A50([.,]00)? ?MAD\z/)  # 1 returned x 50,00
    end

    it "hides the deductions card when there is no penalty and nothing pending" do
      agent.update!(return_penalty_cents: 0)
      AgentDeduction.delete_all

      get "/admin/confirmations/center"

      expect(document.at_css("[data-card=deductions]")).to be_nil
      expect(document.at_css("[data-card=due]")).to be_present
    end

    it "counts every tab from the same rules" do
      get "/admin/confirmations/center"

      expect(%w[pending rescheduled failed planned confirmed delivered returns cancelled paid blocked].to_h { |tab| [ tab, count(tab) ] }).to eq(
        "pending" => 3, "rescheduled" => 1, "failed" => 1, "planned" => 1, "confirmed" => 1,
        "delivered" => 2, "returns" => 1, "cancelled" => 1, "paid" => 1, "blocked" => 1
      )
    end

    it "lists only her orders and the unassigned ones, never what Omar holds or confirmed" do
      get "/admin/confirmations/center", params: { tab: "pending" }
      expect(numbers).to contain_exactly("Q1", "Q2", "Q3")
      expect(document.text).not_to include("OMAR1")

      get "/admin/confirmations/center", params: { tab: "delivered" }
      expect(numbers.size).to eq(2)
      expect(document.css("[data-amount]").map { |cell| cell["data-amount"].to_i }.sum).to eq(40_000)
    end

    it "shows the failed deliveries alert with a link to the failures" do
      get "/admin/confirmations/center"

      alert = document.at_css("[data-failed-alert]")
      expect(alert.text).to include("1 livraisons échouées").or include("1 failed deliveries")
      expect(alert.at_css("a")["href"]).to include("tab=failed")
    end

    it "disables Appeler, WhatsApp and Bloquer until she clocks in, then enables them" do
      get "/admin/confirmations/center"
      expect(document.at_css("[data-clock-in-required]")).to be_present
      expect(document.css("span[data-call].cursor-not-allowed").size).to eq(3)                    # a plain, greyed label: nothing to open yet
      expect(document.css("a[data-call]")).to be_empty

      ConfirmationShift.create!(store: store, user: agent, started_at: 1.hour.ago)
      get "/admin/confirmations/center"
      expect(document.at_css("[data-clock-in-required]")).to be_nil
      expect(document.css("a[data-call][data-turbo-frame=order-modal]").size).to eq(3)
    end

    it "keeps her out of the manager-only actions and the order-creation button" do
      get "/admin/confirmations/center"
      expect(document.text).not_to include("Créer une commande")
      expect(document.text).not_to include("Create order")
    end

    it "filters by search, source and WhatsApp status" do
      get "/admin/confirmations/center", params: { tab: "pending", q: "Queue 2" }
      expect(numbers).to eq([ "Q2" ])

      get "/admin/confirmations/center", params: { tab: "pending", source: "manual" }
      expect(numbers.size).to eq(3)

      Order.find_by!(number: "Q1").record_event!("whatsapp", body: "WhatsApp opened by Saida", user: agent)
      get "/admin/confirmations/center", params: { tab: "pending", whatsapp: "sent" }
      expect(numbers).to eq([ "Q1" ])
      expect(document.at_css("[data-whatsapp=sent]").text).to include("Envoyé").or include("Sent")
      get "/admin/confirmations/center", params: { tab: "pending", whatsapp: "not_sent" }
      expect(numbers).to contain_exactly("Q2", "Q3")
    end

    it "filters by product" do
      other = store.products.create!(name: "Cap", price_cents: 5_000, status: "active")
      Order.find_by!(number: "Q3").order_items.update_all(product_id: other.id)

      get "/admin/confirmations/center", params: { tab: "pending", product: other.id }

      expect(numbers).to eq([ "Q3" ])
    end

    it "sorts newest or oldest first" do
      Order.find_by!(number: "Q1").update_columns(created_at: 3.days.ago)
      get "/admin/confirmations/center", params: { tab: "pending", sort: "oldest" }
      expect(numbers.first).to eq("Q1")
      get "/admin/confirmations/center", params: { tab: "pending", sort: "recent" }
      expect(numbers.last).to eq("Q1")
    end
  end

  describe "the unreachable orders" do
    before do
      order(disposition: "no_answer", number: "NA1", name: "Karim", phone: "0655555551")
      order(disposition: "no_answer", number: "NA2", name: "Salma", phone: "0655555552", assigned: omar)           # held by another agent: not hers
      sign_in(agent)
    end

    it "have their own tab, with the call button, listing only orders whose last call got no answer" do
      get "/admin/confirmations/center", params: { tab: "unreachable" }

      expect(numbers).to eq([ "NA1" ])
      expect(count("unreachable")).to eq(1)
      expect(document.at_css("[data-tab=unreachable]").text).to include("Injoignables")
    end

    it "show their call count in yellow, with the word Injoignable, in every list; other orders stay grey" do
      get "/admin/confirmations/center", params: { tab: "pending" }

      yellow = document.at_css("[data-order-row=NA1] [data-calls]")
      expect(yellow["data-unreachable"]).to eq("yes")
      expect(yellow.at_css("span")["class"]).to include("bg-[#fbe08a]")
      expect(yellow.text).to include("Injoignable")
      grey = document.at_css("[data-order-row=Q1] [data-calls]")
      expect(grey["data-unreachable"]).to eq("no")
      expect(grey.at_css("span")["class"]).to include("bg-[#efeff3]")
      expect(grey.text).not_to include("Injoignable")
    end
  end

  describe "the open tab" do
    before { sign_in(agent) }

    it "takes its own colour instead of black: waiting is yellow, unreachable orange, failed red, confirmed green" do
      { "pending" => "bg-[#f5c242]", "unreachable" => "bg-[#f2994a]", "failed" => "bg-[#e5484d]", "confirmed" => "bg-[#3aa76d]" }.each do |tab, colour|
        get "/admin/confirmations/center", params: { tab: tab }

        classes = document.at_css("[data-tab=#{tab}]")["class"]
        expect(classes).to include(colour), tab
        expect(classes).not_to include("bg-[#1c1c1e]"), tab
        expect(document.at_css("[data-tab=#{tab}]")["aria-current"]).to eq("page")
        expect(document.css("[data-tab]:not([aria-current])").map { |other| other["class"] }.join).not_to include(colour)
      end
    end
  end

  describe "an owner" do
    before { sign_in(owner) }

    it "sees the whole store and no commission cards, with the create-order button" do
      get "/admin/confirmations/center"

      expect(response).to have_http_status(:ok)
      expect(value("confirmed")).to eq("7")   # Saida's 6 + Omar's 1
      expect(value("delivered")).to eq("3")
      expect(value("cancelled")).to eq("1")
      expect(document.at_css("[data-card=due]")).to be_nil
      expect(document.text).to include("Créer une commande").or include("Create order")
    end

    it "lists blocked orders with an unblock button" do
      get "/admin/confirmations/center", params: { tab: "blocked" }

      expect(numbers).to eq([ "BLK1" ])
      expect(document.css("form[action$='/unblock']").size).to eq(1)
    end
  end

  it "never shows another store's orders" do
    foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    stranger = foreign.customers.create!(name: "X", phone: "0699999999")
    foreign.orders.create!(customer: stranger, number: "FOREIGN1", status: "new", currency: "MAD", customer_name: "X", customer_phone: "0699999999",
      customer_city: "Fès", customer_address: "x", subtotal_cents: 100, total_cents: 100)
    sign_in(agent)

    get "/admin/confirmations/center", params: { tab: "pending" }

    expect(document.text).not_to include("FOREIGN1")
  end

  it "requires a session" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin/confirmations/center"
    expect(response).to redirect_to("/admin/login")
  end
end
