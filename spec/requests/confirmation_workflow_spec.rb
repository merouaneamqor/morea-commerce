require "rails_helper"

RSpec.describe "Manager to confirmation-agent workflow", type: :request do
  after { travel_back }

  let(:password) { "synthetic-workflow-password-123" }
  let(:store) { Store.create!(slug: "workflow-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:owner) do
    store.users.create!(name: "Synthetic manager", email: "manager-#{SecureRandom.hex(5)}@example.test",
      password: password, admin: true, confirmation_role: "supervisor")
  end
  let!(:product) { store.products.create!(name: "Synthetic tracksuit", price_cents: 20_000, status: "active", track_inventory: true, stock: 20) }

  def browser
    ActionDispatch::Integration::Session.new(Rails.application).tap { |session| session.host! "#{store.slug}.#{Store.base_domain}" }
  end

  def login(session, user)
    session.post "/admin/login", params: { email: user.email, password: password, locale: "en" }
    expect(session.response).to have_http_status(:redirect)
  end

  def document(session)
    Nokogiri::HTML(session.response.body)
  end

  def create_order(session, name: "Synthetic buyer")
    session.post "/admin/orders", params: { order: { name: name, phone: "0612345678", city: "Casablanca", address: "Synthetic street",
      shipping_dh: "30", lines: { "0" => { product_id: product.id, quantity: "2" } } } }
    expect(session.response).to have_http_status(:redirect), session.response.body
    store.orders.order(:id).last!
  end

  def create_agent(session)
    email = "agent-#{SecureRandom.hex(5)}@example.test"
    session.post "/admin/staff", params: { user: { name: "Synthetic agent", email: email,
      confirmation_role: "agent", admin: "1", password: password, password_confirmation: password } }
    expect(session.response).to have_http_status(:redirect), session.response.body
    store.users.find_by!(email: email)
  end

  it "creates an ordinary order and staff agent through forms, calls and confirms, then shows both users the saved results" do
    manager = browser
    login(manager, owner)
    order = create_order(manager)
    agent = create_agent(manager)
    expect(agent).to have_attributes(admin: false, confirmation_role: "agent")
    expect(order).to have_attributes(status: "new", total_cents: 43_000)
    expect(order.order_confirmation&.assigned_user_id).to be_nil

    worker = browser
    login(worker, agent)
    worker.post "/admin/confirmations/clock_in"
    expect(worker.response).to have_http_status(:redirect)
    worker.get "/admin/confirmations"
    expect(worker.response).to have_http_status(:ok)
    expect(document(worker).at_css("[data-agent-desk]")).to be_present
    expect(document(worker).text).to include(I18n.t("admin.confirmations.step_call"))
    expect(document(worker).at_css("form[action='/admin/confirmations/clock_in']")).to be_nil
    call_path = "/admin/confirmations/#{order.id}/call"
    expect(document(worker).at_css("form[action='#{call_path}'] button:not([disabled])")).to be_present

    worker.post call_path
    expect(worker.response).to have_http_status(:redirect)
    expect(URI(worker.response.location).request_uri).to eq("/admin/confirmations?filter=mine")
    expect(order.reload.order_confirmation).to have_attributes(assigned_user_id: agent.id, call_started_at: be_present)
    worker.get "/admin/confirmations", params: { filter: "mine" }
    finish_path = "/admin/confirmations/#{order.id}/finish_call"
    finish_form = document(worker).at_css("form[action='#{finish_path}']")
    expect(finish_form).to be_present
    expect(finish_form.css("[name='outcome'][value='confirmed'], [name='outcome'] option[value='confirmed']")).not_to be_empty

    travel 40.seconds
    # Desk-presence heartbeat keeps the session inside the 45s grace window across the call.
    ConfirmationShift.open.where(store: store, user: agent).update_all(last_seen_at: Time.current)
    travel 44.seconds
    ConfirmationShift.open.where(store: store, user: agent).update_all(last_seen_at: Time.current)
    worker.post finish_path, params: { outcome: "confirmed", notes: "Synthetic successful call; no telephone connection" }
    expect(worker.response).to have_http_status(:redirect)
    expect(URI(worker.response.location).request_uri).to eq("/admin/confirmations?filter=mine")
    expect(order.reload.status).to eq("confirmed")
    attempt = ConfirmationAttempt.where(store: store, user: agent).sole
    expect(attempt).to have_attributes(outcome: "confirmed", call_seconds: be >= 83)
    expect(order.order_confirmation.reload.call_started_at).to be_nil
    expect(product.reload.stock).to eq(18)
    expect(order.sendit_code).to be_blank

    worker.get "/admin/my_stats"
    expect(worker.response).to have_http_status(:ok)
    expect(document(worker).at_css("[data-kpi=confirmed] [data-value]").text.strip).to start_with("1")
    worker.get "/admin/confirmations/home"
    expect(worker.response).to have_http_status(:ok)
    expect(document(worker).css("div.grid.grid-cols-2 > .admin-card .admin-metric__value").first.text.strip).to eq("10")
    expect(worker.response.body).to include(order.number)

    manager.get "/admin/confirmations/dashboard", params: { period: "today" }
    expect(manager.response).to have_http_status(:ok)
    row = document(manager).css("tbody tr").find { |candidate| candidate.at_css("td")&.text&.strip == agent.name }
    expect(row).to be_present
    cells = row.css("td").map { |cell| cell.text.strip }
    expect(cells[4..5]).to eq(%w[1 1]) # attempts and confirmed, from the saved call
    manager.get "/admin/orders", params: { group: "confirmed" }
    expect(manager.response).to have_http_status(:ok)
    expect(manager.response.body).to include(order.number)
    expect(manager.response.body).to include(agent.name)

    worker.get "/admin/staff"
    expect(worker.response).to have_http_status(:redirect)
    expect(URI(worker.response.location).path).to eq("/admin/my_stats")
  end

  it "preserves contact and order lines when the call sends only an address correction" do
    manager = browser
    login(manager, owner)
    order = create_order(manager)
    agent = create_agent(manager)
    worker = browser
    login(worker, agent)
    worker.post "/admin/confirmations/clock_in"
    expect(worker.response).to have_http_status(:redirect)
    worker.post "/admin/confirmations/#{order.id}/call", as: :json
    expect(worker.response).to have_http_status(:ok)

    worker.post "/admin/confirmations/#{order.id}/finish_call", params: {
      outcome: "confirmed", order: { address: "Corrected synthetic street" }
    }, as: :json

    expect(worker.response).to have_http_status(:ok), worker.response.body
    expect(order.reload).to have_attributes(status: "confirmed", customer_address: "Corrected synthetic street", customer_name: "Synthetic buyer", total_cents: 43_000)
    expect(order.order_items.sole).to have_attributes(product_id: product.id, quantity: 2)
    expect(ConfirmationAttempt.where(store: store, user: agent).sole.outcome).to eq("confirmed")
  end

  it "rejects an unusable supervisor account without silently granting manager access" do
    manager = browser
    login(manager, owner)
    email = "supervisor-#{SecureRandom.hex(5)}@example.test"
    manager.post "/admin/staff", params: { user: { name: "Synthetic supervisor", email: email,
      confirmation_role: "supervisor", admin: "0", password: password, password_confirmation: password } }
    expect(manager.response).to have_http_status(:unprocessable_content)
    expect(store.users.exists?(email: email)).to be(false)

    manager.post "/admin/staff", params: { user: { name: "Synthetic supervisor", email: email,
      confirmation_role: "supervisor", admin: "1", password: password, password_confirmation: password } }
    expect(manager.response).to have_http_status(:redirect)
    supervisor = store.users.find_by!(email: email)
    expect(supervisor.admin?).to be(true)
    supervisor_browser = browser
    login(supervisor_browser, supervisor)
    supervisor_browser.get "/admin/confirmations/dashboard"
    expect(supervisor_browser.response).to have_http_status(:ok)
  end
end
