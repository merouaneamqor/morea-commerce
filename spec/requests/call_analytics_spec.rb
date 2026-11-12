require "rails_helper"
require "nokogiri"

RSpec.describe "Call center analytics page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ca-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def kpi(key) = page.at_css("[data-kpi=#{key}] [data-value]").text.squish
  def make(number, status: "new", confirmed: false, delivered: false)
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.update_columns(status: status, cancelled_at: (Time.current if status == "cancelled"), confirmed_at: (Time.current if confirmed), shipped_at: (Time.current if delivered), delivered_at: (Time.current if delivered))
    record
  end

  def call(order, outcome, user)
    confirmation = OrderConfirmation.find_or_create_by!(store: store, order: order) { |row| row.disposition = "pending" }
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: user, outcome: outcome)
  end

  before do
    first = make("A1", status: "delivered", confirmed: true, delivered: true)
    second = make("A2", status: "confirmed", confirmed: true)
    third = make("A3", status: "cancelled")
    make("A4")
    call(first, "confirmed", agent)
    call(second, "no_answer", omar)
    call(second, "confirmed", omar)
    call(third, "cancelled", agent)
  end

  it "prints the figures of the period for the owner, from the same numbers as the service" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601 }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to include("Analyses")
    expect(kpi("confirmation_rate")).to eq("50,0 %")                                   # 2 confirmed of 4 assigned
    expect(kpi("delivery_rate")).to eq("50,0 %")                                       # 1 delivered of 2 confirmed
    expect(kpi("delivered_per_100")).to eq("25,0 %")
    expect(kpi("waiting")).to eq("1")                                                  # A4 has no call
    expect(page.css("[data-stage]").map { |stage| [ stage["data-stage"], stage["data-count"].to_i ] }).to eq([ [ "assigned", 4 ], [ "reached", 3 ], [ "confirmed", 2 ], [ "shipped", 1 ], [ "delivered", 1 ] ])
    expect(page.css("[data-outcome]").to_h { |row| [ row["data-outcome"], row["data-count"].to_i ] }).to include("confirmed" => 2, "no_answer" => 1, "cancelled" => 1)
    expect(page.at_css("[data-total-calls]").text.squish).to eq("4")
    expect(page.at_css("[data-cancel-reasons]").text).to include("Sans motif")           # the cancelled order has no reason
    expect(page.css("[data-heatmap] [data-cell]").size).to eq(7 * 24)
    expect(page.css("[data-day]").size).to eq(1)
    expect(page.at_css("[data-method-note]").text).to include("upsell")                # said plainly: not computed yet
  end

  it "gives the owner the three views: overview, compare the agents, one agent" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601 }

    tabs = page.at_css("[data-analytics-tabs]")
    expect(tabs.at_css("[data-tab=overview]")["aria-current"]).to eq("page")
    expect(tabs.at_css("[data-tab=compare]")["href"]).to eq("/admin/confirmations/dashboard")
    expect(tabs.css("select[data-tab=agent] option").map(&:text)).to include("Agent", "Saida", "Omar")

    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, agent_id: agent.id }
    expect(page.at_css("[data-analytics-tabs] select[data-tab=agent]")["aria-current"]).to eq("page")
    expect(page.at_css("h1 + p").text).to include("Saida")
    expect(page.css("[data-stage]").map { |stage| stage["data-count"].to_i }).to eq([ 2, 2, 1, 1, 1 ])   # her two orders: A1 delivered, A3 cancelled
  end

  it "shows an agent only her own calls, without the owner's tabs, whatever agent_id says" do
    sign_in(agent)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, agent_id: omar.id }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-analytics-tabs]")).to be_nil
    expect(page.at_css("[data-total-calls]").text.squish).to eq("2")                    # Saida made two of the four calls
    expect(page.at_css("h1 + p").text).to include("Saida")
  end

  it "is reached from the menu entry Analyses and marks it as the current page" do
    sign_in(owner)
    get "/admin/confirmations/analytics"

    expect(page.at_css("[data-subnav-item=analytics]")["aria-current"]).to eq("page")
    expect(page.at_css("[data-call-center-nav]").has_attribute?("open")).to be(true)
  end

  it "keeps another store's calls and orders out of the figures" do
    other = Store.create!(slug: "ca-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    foreign_customer = other.customers.create!(name: "X", phone: "0611111111")
    foreign = other.orders.create!(customer: foreign_customer, number: "F1", status: "confirmed", currency: "MAD", customer_name: "X", customer_phone: "0611111111", customer_city: "Fès", customer_address: "a", subtotal_cents: 100, total_cents: 100)
    foreign.update_columns(confirmed_at: Time.current)
    sign_in(owner)

    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601 }

    expect(page.css("[data-stage]").first["data-count"].to_i).to eq(4)
  end

  it "gives each stage of an order one colour, the same on every chart: blue, sky blue, green, purple, dark green" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601 }

    colours = page.css("[data-stage]").to_h { |row| [ row["data-stage"], row.at_css("span[data-grow]")["style"][/background: (#\h+)/, 1] ] }
    expect(colours).to eq("assigned" => "#2a78d6", "reached" => "#5ab4ef", "confirmed" => "#5bc98f", "shipped" => "#8b5cf6", "delivered" => "#136b3d")
    expect(page.at_css("[data-day] span[style*='#5bc98f']")).to be_present                       # the confirmed part of a day is the confirmed green
    expect(page.at_css("[data-rates-chart]").to_html).to include("#5bc98f", "#136b3d")            # confirmation and delivery lines
    expect(page.at_css("[data-hourly]").to_html).to include("#2a78d6")                            # new orders are the received blue
    expect(page.css("[data-heatmap] [data-cell]:not([data-calls='0'])").first["style"]).to include("rgba(90, 180, 239")   # answered calls: the sky blue of "reached"
  end
end
