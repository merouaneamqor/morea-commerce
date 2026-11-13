require "rails_helper"
require "nokogiri"

# What a confirmation agent sees: their own dashboard, their own call center queue (as the owner's attribution rules decide) and their own billing.
RSpec.describe "Agent workspace", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ag-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def host = "#{store.slug}.#{Store.base_domain}"

  def make(number, attributed: nil)
    order = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    OrderConfirmation.create!(store: store, order: order, disposition: "pending", attributed_user: attributed) if attributed
    order
  end

  def queue_numbers = page.css("[data-order-row], [data-order-number]").map { |node| node["data-order-row"] || node["data-order-number"] }

  it "gives the agent a menu with only their dashboard, their call center and their billing" do
    sign_in(saida)
    get admin_my_stats_path

    expect(response).to have_http_status(:ok)
    labels = page.css("[data-sidebar-nav] > ul > li").map { |item| item.text.squish }
    expect(labels.join(" ")).to include("Tableau de bord", "Centre d'appels", "Facturation")
    expect(page.at_css("[data-sidebar-nav]").text).not_to include("Comptabilité", "Équipe", "Produits", "Commandes", "Clients", "Livraison")
  end

  it "shows an agent only their own payments and deductions in Facturation" do
    AgentPayment.create!(store: store, user: saida, amount_cents: 1600, paid_at: 2.days.ago)
    AgentPayment.create!(store: store, user: omar, amount_cents: 99_900, paid_at: 1.day.ago)
    sign_in(saida)
    get admin_my_billing_path

    expect(response).to have_http_status(:ok)
    expect(page.css("[data-payment]").size).to eq(1)
    expect(response.body).to include("16 MAD")
    expect(response.body).not_to include("999 MAD")
    expect(response.body).not_to include(omar.name)
  end

  it "keeps the other pages of the store closed to an agent" do
    sign_in(saida)
    get admin_users_path
    expect(response).to redirect_to(home_admin_confirmations_path)
    get admin_accounting_path
    expect(response).to redirect_to(home_admin_confirmations_path)
  end

  it "follows the owner's attribution rules: with an active rule an agent sees only the orders given to them" do
    mine = make("MINE", attributed: saida)
    make("THEIRS", attributed: omar)
    open_pool = make("OPEN")
    sign_in(saida)

    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).to include("OPEN") # no rule yet: the open pool is shared

    rule = store.assignment_rules.new(name: "Règle", distribution: "equal")
    [ saida, omar ].each { |agent| rule.assignment_rule_agents.build(user: agent) }
    rule.save!

    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).to include("MINE")
    expect(response.body).not_to include("THEIRS")
    expect(response.body).not_to include("OPEN")
    get admin_order_path(open_pool)
    expect(response).to have_http_status(:not_found)
    get admin_order_path(mine)
    expect(response).to have_http_status(:ok)
  end
  it "clocks in and out in place, and counts the time in the agent's own statistics" do
    sign_in(saida)
    get "/admin/confirmations/center"
    expect(response).to have_http_status(:ok)

    post clock_in_admin_confirmations_path, headers: { "HTTP_REFERER" => "http://#{host}/admin/confirmations/center" }
    expect(response).to redirect_to("http://#{host}/admin/confirmations/center")
    expect(ConfirmationShift.open.where(user: saida)).to exist
    follow_redirect!
    expect(page.at_css("[data-shift-running]")).to be_present

    ConfirmationShift.open.find_by(user: saida).update_columns(started_at: 90.minutes.ago)
    get admin_my_stats_path
    expect(page.at_css("[data-my-hours] [data-worked]")["data-worked"].to_i).to be_between(5390, 5500)
    expect(page.at_css("[data-my-hours]").text).to include("1:3")

    post clock_out_admin_confirmations_path, headers: { "HTTP_REFERER" => "http://#{host}/admin/my_stats" }
    expect(response).to redirect_to("http://#{host}/admin/my_stats")
    expect(ConfirmationShift.open.where(user: saida)).not_to exist
  end

  it "shows the owner each agent's time worked next to the comparison" do
    owner = store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
    ConfirmationShift.create!(store: store, user: saida, started_at: 2.hours.ago, ended_at: 30.minutes.ago)
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { view: "agents" }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-hours-head]")).to be_present
    expect(page.at_css("[data-agent-row='#{saida.id}'] [data-worked]")["data-worked"].to_i).to be_between(5390, 5410)
    expect(page.at_css("[data-agent-row='#{omar.id}'] [data-worked]")["data-worked"]).to eq("0")
  end
end
