require "rails_helper"
require "nokogiri"

RSpec.describe "Orders flow, from creation to confirmation", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "flow-#{SecureRandom.hex(5)}", name: "Flow", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:other_agent) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:product) { store.products.create!(name: "Survêtement Été", sku: "SURV-01", price_cents: 25_000, status: "active", track_inventory: true, stock: 10) }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document = Nokogiri::HTML(response.body)

  def create_order(lines: [ { product_id: product.id, quantity: 2 } ], extra: {})
    post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", shipping_dh: 30, lines: lines }.merge(extra) }
  end

  def search(query)
    get "/admin/orders/product_search", params: { q: query }
    JSON.parse(response.body).map { |item| item["label"] }
  end

  describe "creating an order" do
    before { sign_in(owner) }

    it "finds a product by part of its name, ignoring case and accents, or by SKU" do
      expect(search("survet")).to eq([ "Survêtement Été" ])
      expect(search("SURVETEMENT ete")).to eq([ "Survêtement Été" ])
      expect(search("tement")).to eq([ "Survêtement Été" ])
      expect(search("surv-01")).to eq([ "Survêtement Été" ])
      expect(search("zzz")).to eq([])
    end

    it "lists the first 10 products, by name, when the field is empty" do
      12.times { |i| store.products.create!(name: "Article #{format('%02d', i)}", price_cents: 1_000, status: "active") }

      labels = search("")

      expect(labels.size).to eq(10)
      expect(labels).to eq(labels.sort_by { |label| I18n.transliterate(label).downcase })
    end

    it "never lists another store's products" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      foreign.products.create!(name: "Survêtement secret", price_cents: 1_000, status: "active")

      expect(search("secret")).to eq([])
    end

    it "creates a missing product on the spot and returns it as a pickable line" do
      expect { post "/admin/orders/quick_product", params: { name: "Casquette", price: "49,50" } }.to change { store.products.count }.by(1)

      expect(response).to have_http_status(:created)
      item = JSON.parse(response.body)
      expect(item).to include("label" => "Casquette", "price_cents" => 4_950)
      expect(store.products.find(item["product_id"])).to have_attributes(status: "active", price_cents: 4_950)
      expect(search("casq")).to eq([ "Casquette" ])
    end

    it "refuses a quick product without a name or with a price of 0" do
      expect { post "/admin/orders/quick_product", params: { name: "", price: "10" } }.not_to change { store.products.count }
      expect(response).to have_http_status(:unprocessable_content)
      expect { post "/admin/orders/quick_product", params: { name: "Free", price: "0" } }.not_to change { store.products.count }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "blocks an order with no product" do
      expect { create_order(lines: []) }.not_to change { store.orders.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.text).to include("Add at least one product.")
    end

    it "blocks an order whose total is 0" do
      free = store.products.create!(name: "Gift", price_cents: 0, status: "active")

      expect { create_order(lines: [ { product_id: free.id, quantity: 1 } ], extra: { shipping_dh: 0 }) }.not_to change { store.orders.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(document.text).to include("The order total must be above 0 MAD.")
    end

    it "disables the Create button until a product is added" do
      get "/admin/orders/new"

      expect(document.at_css("input[type=submit][data-order-lines-target=submit]")).to be_present
    end
  end

  describe "assignment" do
    before { sign_in(owner) }

    it "leaves a manual order unassigned: not the person who created it" do
      create_order

      order = store.orders.order(:id).last
      expect(order.order_confirmation&.assigned_user_id).to be_nil
      expect(order.order_events.where(kind: "created").first.user).to eq(owner)
    end

    it "assigns to the agent picked in the optional field" do
      create_order(extra: { agent_id: agent.id })

      order = store.orders.order(:id).last
      expect(order.order_confirmation.assigned_user).to eq(agent)
    end

    it "refuses an owner or another store's agent in that field" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = foreign.users.create!(name: "Stranger", email: "s-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")
      [ owner, stranger ].each do |person|
        expect { create_order(extra: { agent_id: person.id }) }.not_to change { store.orders.count }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "offers only the store's agents in the form" do
      agent
      other_agent
      get "/admin/orders/new"

      names = document.css("select[name='order[agent_id]'] option").map(&:text)
      expect(names).to include("Saida", "Omar")
      expect(names).not_to include("Owner")
    end
  end

  describe "the orders table" do
    before { sign_in(owner) }

    it "shows Manuel for a manual order, the columns of the new page in order, and one scrolling wrap" do
      create_order

      get "/admin/orders"

      headers = document.css("thead th").map { |th| th.text.squish }
      expect(headers).to eq(%w[id created customer product amount confirmation shipping source delivery city actions].map { |key| I18n.t("orders_page.columns.#{key}") })
      expect(document.at_css("[data-source]").text.squish).to eq(I18n.t("orders_page.filters.manual"))
      expect(document.css("[data-orders-table-wrap]").size).to eq(1)
    end
  end

  describe "the agent side" do
    let!(:waiting) { store.orders.find_by!(id: create_as_owner) }

    def create_as_owner
      sign_in(owner)
      create_order
      store.orders.order(:id).last.id
    end

    it "shows an unassigned order to every agent in Available now, without a shift" do
      [ agent, other_agent ].each do |person|
        sign_in(person)
        get "/admin/confirmations", params: { filter: "available" }
        expect(response).to have_http_status(:ok)
        expect(document.text).to include("##{waiting.number}")
      end
    end

    it "opens Orders for an agent: their own and unassigned orders, never another agent's, without costs" do
      other = store.orders.create!(customer: waiting.customer, customer_name: "Hidden", customer_phone: "0612345678", customer_city: "Fès", customer_address: "x",
        subtotal_cents: 1_000, total_cents: 1_000, currency: "MAD", status: "new")
      OrderConfirmation.create!(store: store, order: other, assigned_user: other_agent, claimed_at: Time.current)
      mine = store.orders.create!(customer: waiting.customer, customer_name: "Mine", customer_phone: "0612345678", customer_city: "Fès", customer_address: "x",
        subtotal_cents: 1_000, total_cents: 1_000, currency: "MAD", status: "new")
      OrderConfirmation.create!(store: store, order: mine, assigned_user: agent, claimed_at: Time.current)

      sign_in(agent)
      get "/admin/orders"

      expect(response).to have_http_status(:ok)
      numbers = document.css("[data-order-row]").map { |row| row["data-order-row"] }
      expect(numbers).to contain_exactly(waiting.number, mine.number)
      expect(document.text).not_to match(/Sendit|Create order|profit|cost/i)

      get "/admin/orders/#{mine.id}"
      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-agent-order]")).to be_present
      expect(document.text).not_to match(/profit|cost|margin/i)

      get "/admin/orders/#{other.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "lets agents look and create orders (attributed to them), but not change existing ones" do
      sign_in(agent)

      get "/admin/orders/new"
      expect(response).to have_http_status(:ok)
      expect { create_order }.to change { store.orders.count }.by(1)
      expect(store.orders.order(:id).last.order_confirmation.attributed_user_id).to eq(agent.id)
      patch "/admin/orders/#{waiting.id}/transition", params: { to_status: "confirmed" }
      expect(waiting.reload.status).to eq("new")
    end

    it "needs a shift to claim: disabled buttons and a message, and the server refuses too" do
      sign_in(agent)
      get "/admin/confirmations"

      expect(document.at_css("[data-clock-in-required]").text).to include(I18n.t("admin.confirmations.clock_in_required"))
      expect(document.css("form[action$='/claim'] button[disabled], form[action$='/claim'] input[disabled]").size).to eq(1)

      post "/admin/confirmations/#{waiting.id}/claim"

      expect(flash[:alert]).to eq(I18n.t("admin.confirmations.clock_in_required"))
      expect(waiting.reload.order_confirmation&.assigned_user_id).to be_nil
    end

    it "refuses an outcome from an agent who clocked out, even when they hold the order" do
      sign_in(agent)
      post "/admin/confirmations/clock_in"
      post "/admin/confirmations/#{waiting.id}/claim"
      post "/admin/confirmations/clock_out"

      post "/admin/confirmations/#{waiting.id}/outcome", params: { outcome: "confirmed" }

      expect(flash[:alert]).to eq(I18n.t("admin.confirmations.clock_in_required"))
      expect(waiting.reload.status).to eq("new")
    end
  end

  it "runs the whole flow: owner creates, agent claims and confirms, owner and Team see it" do
    # Owner creates an order with a product.
    sign_in(owner)
    create_order
    order = store.orders.order(:id).last
    expect(order).to have_attributes(status: "new", total_cents: 53_000)  # 2 x 250,00 + 30,00 shipping
    expect(order.order_confirmation&.assigned_user_id).to be_nil

    # The agent sees it in "Available now".
    sign_in(agent)
    get "/admin/confirmations", params: { filter: "available" }
    expect(document.text).to include("##{order.number}", "Survêtement Été")

    # Clock in, claim, confirm.
    post "/admin/confirmations/clock_in"
    expect(ConfirmationShift.open.where(store: store, user: agent).count).to eq(1)
    post "/admin/confirmations/#{order.id}/claim"
    expect(order.reload.order_confirmation.assigned_user).to eq(agent)
    post "/admin/confirmations/#{order.id}/outcome", params: { outcome: "confirmed", notes: "Customer agreed" }
    expect(flash[:alert]).to be_nil

    # The owner sees it Confirmed.
    expect(order.reload.status).to eq("confirmed")
    sign_in(owner)
    get "/admin/orders/#{order.id}"
    expect(document.text).to include("Confirmed")
    get "/admin/orders", params: { group: "confirmed" }
    expect(document.css("[data-order-row]").map { |row| row["data-order-row"] }).to eq([ order.number ])

    # The agent's points went up (10 per confirmation).
    home = Confirmations::AgentHome.new(store: store, user: agent, range: Time.current.beginning_of_day..Time.current.end_of_day)
    expect(home.points).to eq(10)
    expect(home.outcome_counts["confirmed"]).to eq(1)
    sign_in(agent)
    get "/admin/confirmations/home"
    expect(document.text).to match(/\b10\b/)

    # The Team page shows the agent's confirmations of the month in their row.
    sign_in(owner)
    get "/admin/staff"
    expect(document.at_css("[data-member='#{agent.id}']").text.squish).to include("1 / 0")
    expect(document.text).to include("Saida")
    month = Time.current.beginning_of_month..Time.current.end_of_month
    expect(Team::AgentEarnings.new(store: store, range: month).summary_for(agent).figures.confirmed).to eq(1)
  end
end
