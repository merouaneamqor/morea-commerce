require "rails_helper"
require "nokogiri"

RSpec.describe "Confirmation dashboard", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "desk-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:staff) { store.users.create!(name: "Ana", email: "ana-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def sign_in(user = staff, workspace: store)
    host! "#{workspace.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "requires an admin session" do
    host! "#{store.slug}.#{Store.base_domain}"

    get "/admin/confirmations/dashboard"

    expect(response).to redirect_to("/admin/login")
  end

  it "shows roles, hours and confirmation results for the store" do
    sign_in
    ConfirmationShift.create!(store: store, user: staff, started_at: 90.minutes.ago)
    customer = store.customers.create!(name: "Buyer", phone: "0612345678", city: "Casablanca")
    order = store.orders.create!(customer: customer, customer_name: "Buyer", customer_phone: "0612345678",
      customer_city: "Casablanca", customer_address: "Address", total_cents: 101, subtotal_cents: 101, currency: "MAD", status: "new")
    confirmation = OrderConfirmation.create!(store: store, order: order)
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: staff, outcome: "confirmed")

    get "/admin/confirmations/dashboard", params: { period: "today" }

    expect(response).to have_http_status(:ok)
    expect(document.text).to include("Ana", I18n.t("admin.confirmations.roles.supervisor"), I18n.t("admin.confirmations.status.on_shift"), I18n.t("admin.confirmations.performance_title"))
    expect(document.css("[role=timer]").size).to eq(1)
    expect(document.css("form[action^='/admin/confirmations/clock_out']").size).to eq(1)
  end

  it "keeps another workspace's attempts out of the dashboard" do
    sign_in
    foreign = Store.create!(slug: "other-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    outsider = foreign.users.create!(name: "Outsider", email: "outsider-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    customer = foreign.customers.create!(name: "Buyer", phone: "0612345678", city: "Casablanca")
    order = foreign.orders.create!(customer: customer, customer_name: "Buyer", customer_phone: "0612345678",
      customer_city: "Casablanca", customer_address: "Address", total_cents: 101, subtotal_cents: 101, currency: "MAD", status: "new")
    ConfirmationAttempt.create!(store: foreign, order_confirmation: OrderConfirmation.create!(store: foreign, order: order), user: outsider, outcome: "confirmed")

    get "/admin/confirmations/dashboard"

    expect(response).to have_http_status(:ok)
    expect(document.text).not_to include("Outsider")
  end

  it "clocks in and out, refusing a repeated clock-in" do
    sign_in

    post "/admin/confirmations/clock_in", params: { period: "week" }
    expect(response).to redirect_to("/admin/confirmations/dashboard?period=week")
    expect(ConfirmationShift.open.where(store: store, user: staff).count).to eq(1)

    post "/admin/confirmations/clock_in"
    expect(flash[:alert]).to eq("You are already on shift.")
    expect(ConfirmationShift.open.where(store: store, user: staff).count).to eq(1)

    post "/admin/confirmations/clock_out"
    expect(ConfirmationShift.open.where(store: store, user: staff).count).to eq(0)
  end

  it "shows the products of each order in my claims" do
    sign_in
    order = store.orders.create!(customer: store.customers.create!(name: "Buyer", phone: "0612345678", city: "Casablanca"),
      customer_name: "Buyer", customer_phone: "0612345678", customer_city: "Casablanca", customer_address: "Address",
      total_cents: 20_000, subtotal_cents: 20_000, currency: "MAD", status: "new")
    OrderItem.create!(order: order, product_name: "Synthetic tee", variant_name: "M", quantity: 2, unit_price_cents: 10_000, total_cents: 20_000)
    OrderConfirmation.create!(store: store, order: order, assigned_user: staff)

    get "/admin/confirmations", params: { filter: "mine" }

    expect(response).to have_http_status(:ok)
    expect(document.text).to include("2 × Synthetic tee", "(M)", I18n.t("admin.confirmations.products"))
  end

  it "saves the confirmation role from the staff form and rejects unknown roles" do
    sign_in

    patch "/admin/staff/#{staff.id}", params: { user: { name: "Ana", email: staff.email, confirmation_role: "supervisor" } }
    expect(staff.reload.confirmation_role).to eq("supervisor")

    patch "/admin/staff/#{staff.id}", params: { user: { name: "Ana", email: staff.email, confirmation_role: "owner" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(staff.reload.confirmation_role).to eq("supervisor")
  end

  context "as a confirmation agent" do
    let(:agent) { store.users.create!(name: "Lina", email: "lina-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }
    let(:colleague) { store.users.create!(name: "Ben", email: "ben-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }

    def new_order(workspace: store)
      customer = workspace.customers.first || workspace.customers.create!(name: "Buyer", phone: "0612345678", city: "Casablanca")
      workspace.orders.create!(customer: customer, customer_name: "Buyer", customer_phone: "0612345678",
        customer_city: "Casablanca", customer_address: "Address", total_cents: 101, subtotal_cents: 101, currency: "MAD", status: "new")
    end

    it "lands on the desk after sign-in and cannot open other admin pages" do
      sign_in(agent)
      expect(response).to redirect_to("/admin/confirmations/home")

      get "/admin/orders"
      expect(response).to redirect_to("/admin/confirmations/home")
    end

    it "shows points, the orders in hand and time spent on the home page" do
      sign_in(agent)
      held = OrderConfirmation.create!(store: store, order: new_order, assigned_user: agent, claimed_at: 4.minutes.ago)
      ConfirmationAttempt.create!(store: store, order_confirmation: OrderConfirmation.create!(store: store, order: new_order), user: agent,
        outcome: "confirmed", handled_seconds: 90)

      get "/admin/confirmations/home"

      expect(response).to have_http_status(:ok)
      expect(document.text).to include(I18n.t("admin.confirmations.home_title", name: "Lina"), "##{held.order.number}", held.order.customer_name)
      expect(document.css("[role=timer]").size).to be >= 1
      expect(document.text).to include("10 pts")
      expect(document.css("table.admin-table tbody tr").size).to eq(1)
    end

    it "sees only its own figures on the performance page" do
      sign_in(agent)
      ConfirmationAttempt.create!(store: store, order_confirmation: OrderConfirmation.create!(store: store, order: new_order), user: colleague, outcome: "confirmed")
      ConfirmationAttempt.create!(store: store, order_confirmation: OrderConfirmation.create!(store: store, order: new_order), user: agent, outcome: "cancelled")

      get "/admin/confirmations/dashboard"

      expect(response).to have_http_status(:ok)
      expect(document.text).to include("Lina")
      expect(document.text).not_to include("Ben")
      expect(document.css("table.admin-table tbody tr").size).to eq(1)
    end

    it "drops the all-orders view and hides colleagues' names in the queue" do
      sign_in(agent)
      order = new_order
      OrderConfirmation.create!(store: store, order: order, assigned_user: colleague, disposition: "callback", callback_at: 1.minute.ago)

      get "/admin/confirmations", params: { filter: "all" }
      expect(document.css(".admin-tab").map { |tab| tab.text.strip }).not_to include(I18n.t("admin.confirmations.all"))
      expect(document.css(".admin-tab.is-active").text.strip).to eq(I18n.t("admin.confirmations.available"))

      get "/admin/confirmations", params: { filter: "callbacks_due" }
      expect(document.text).to include("##{order.number}")
      expect(document.text).not_to include("Ben")
      expect(document.text).to include(I18n.t("admin.confirmations.claimed_elsewhere"))
    end

    it "claims an order from the queue" do
      sign_in(agent)
      order = new_order

      post "/admin/confirmations/#{order.id}/claim"

      expect(OrderConfirmation.find_by!(order: order).assigned_user_id).to eq(agent.id)
    end
  end
end
