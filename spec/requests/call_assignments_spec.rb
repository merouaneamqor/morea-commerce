require "rails_helper"
require "nokogiri"

RSpec.describe "Call center assignments page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ca-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def numbers = page.css("[data-assignments-table] [data-order-row]").map { |row| row["data-order-row"] }
  def card(agent) = page.at_css("[data-agent-card='#{agent.id}']")

  def make(number, minutes_ago: 60, attributed: nil, disposition: nil)
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.update_columns(created_at: minutes_ago.minutes.ago)
    OrderConfirmation.create!(store: store, order: record, disposition: disposition || "pending", attributed_user: attributed) if attributed || disposition
    record
  end

  before do
    make("W1", minutes_ago: 50)
    make("W2", minutes_ago: 40, disposition: "no_answer")
    make("A1", minutes_ago: 10, attributed: omar)
    ConfirmationShift.create!(store: store, user: saida, started_at: 1.hour.ago)
  end

  it "lists the unattributed orders by default, with the agents' cards under the table" do
    sign_in(owner)
    get "/admin/confirmations/assignments"

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to include("Attributions")
    expect(numbers).to eq(%w[W2 W1])
    expect(page.at_css("[data-order-row=W2] [data-status]")["data-status"]).to eq("no_answer")
    expect(page.at_css("[data-order-row=W1] select[name=agent_id]")["aria-label"]).to eq("Attribuer à")
    expect(page.css("[data-agents-overview] [data-agent-card]").size).to eq(2)
    expect(card(saida)["data-active"]).to eq("true")                                          # clocked in
    expect(card(omar)["data-active"]).to eq("false")
    expect(card(omar).at_css("[data-load]").text.squish).to eq("1/20")                        # A1 is hers... his
    expect(card(omar).at_css("[data-stat=pending]").text.squish).to eq("1")
    expect(page.at_css("[data-auto-assign]").text).to include("Auto-attribuer tout")
  end

  it "filters as the agent, status and missed-call selects say, and clears back to the default" do
    sign_in(owner)

    get "/admin/confirmations/assignments", params: { agent: omar.id }
    expect(numbers).to eq([ "A1" ])
    get "/admin/confirmations/assignments", params: { agent: "all" }
    expect(numbers).to eq(%w[A1 W2 W1])
    get "/admin/confirmations/assignments", params: { status: "no_answer" }
    expect(numbers).to eq([ "W2" ])
    expect(page.at_css("[data-clear-filters]")).to be_present
    get "/admin/confirmations/assignments", params: { q: "nothing like it" }
    expect(page.at_css("[data-empty]").text).to include("Aucune commande ne correspond")
    get "/admin/confirmations/assignments"
    expect(page.at_css("[data-clear-filters]")).to be_nil
  end

  it "says everything is attributed when nothing waits, and disables the automatic attribution" do
    sign_in(owner)
    store.orders.find_by!(number: "W1").tap { |order| OrderConfirmation.create!(store: store, order: order, attributed_user: saida) }
    store.orders.find_by!(number: "W2").order_confirmation.update!(attributed_user: saida)

    get "/admin/confirmations/assignments"

    expect(page.at_css("[data-empty]").text).to include("Toutes les commandes sont attribuées")
    expect(page.at_css("[data-auto-assign]")["disabled"]).to be_present
  end

  it "attributes an order from the select, and removes the attribution" do
    sign_in(owner)
    order = store.orders.find_by!(number: "W1")

    patch "/admin/confirmations/#{order.id}/assign", params: { agent_id: saida.id }
    expect(response).to redirect_to("/admin/confirmations/assignments")
    expect(order.reload.order_confirmation.attributed_user_id).to eq(saida.id)
    follow_redirect!
    expect(response.body).to include("Commande attribuée à Saida.")

    patch "/admin/confirmations/#{order.id}/assign", params: { agent_id: "" }
    expect(order.reload.order_confirmation.attributed_user_id).to be_nil
  end

  it "says why an order cannot be attributed" do
    sign_in(owner)
    order = store.orders.find_by!(number: "W1")

    patch "/admin/confirmations/#{order.id}/assign", params: { agent_id: owner.id }

    expect(order.reload.order_confirmation&.attributed_user_id).to be_nil
    follow_redirect!
    expect(response.body).to include("Choose an agent of this store.")
  end

  it "spreads the unattributed orders over the agents on shift with the button, and says how many it did" do
    sign_in(owner)

    post "/admin/confirmations/auto_assign"

    expect(response).to redirect_to("/admin/confirmations/assignments?agent=all")
    expect(%w[W1 W2].map { |number| store.orders.find_by!(number: number).order_confirmation.attributed_user_id }).to eq([ saida.id, saida.id ])     # only Saida is on shift
    follow_redirect!
    expect(response.body).to include("2 commandes attribuées automatiquement.")
    expect(card(saida).at_css("[data-load]").text.squish).to eq("2/20")
  end

  it "tells the owner when nobody is on shift" do
    sign_in(owner)
    ConfirmationShift.open.update_all(ended_at: Time.current)

    post "/admin/confirmations/auto_assign"

    follow_redirect!
    expect(response.body).to include("No agent is on shift")
    expect(store.orders.find_by!(number: "W1").order_confirmation).to be_nil
  end

  it "is closed to the agents: the page, the attribution and the automatic attribution" do
    sign_in(saida)
    order = store.orders.find_by!(number: "W1")

    get "/admin/confirmations/assignments"
    expect(response).to have_http_status(:forbidden)
    patch "/admin/confirmations/#{order.id}/assign", params: { agent_id: saida.id }
    expect(response).to have_http_status(:forbidden)
    post "/admin/confirmations/auto_assign"
    expect(response).to have_http_status(:forbidden)
    expect(order.reload.order_confirmation).to be_nil
  end

  it "does not touch another store's orders" do
    other = Store.create!(slug: "ca-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    foreign = other.orders.create!(customer: other.customers.create!(name: "X", phone: "0611111111"), number: "F1", status: "new", currency: "MAD", customer_name: "X", customer_phone: "0611111111",
      customer_city: "Fès", customer_address: "a", subtotal_cents: 100, total_cents: 100)
    sign_in(owner)

    patch "/admin/confirmations/#{foreign.id}/assign", params: { agent_id: saida.id }

    expect(response).to redirect_to("/admin/confirmations/assignments")                       # "no longer waiting": it is not this store's order
    expect(foreign.reload.order_confirmation).to be_nil
  end

  it "is the page of the Attributions entry of the menu" do
    sign_in(owner)
    get "/admin/confirmations/assignments"

    expect(page.at_css("[data-subnav-item=assignments]")["aria-current"]).to eq("page")
    expect(page.at_css("[data-subnav-item=assignments]")["href"]).to eq("/admin/confirmations/assignments")
  end
end
