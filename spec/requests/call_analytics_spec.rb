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
    expect(tabs.at_css("[data-tab=compare]")["href"]).to eq("/admin/confirmations/analytics?view=agents")
    expect(tabs.at_css("[data-tab=agent]")["href"]).to eq("/admin/confirmations/analytics?view=agent")      # a tab like the others, not a drop-down
    expect(page.at_css("[data-shifts-link]")).to be_nil                                                  # "Pointage et heures" is gone from the header

    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, agent_id: agent.id }
    expect(page.at_css("[data-analytics-tabs] [data-tab=agent]")["aria-current"]).to eq("page")
    expect(page.at_css("[data-analytics-tabs] [data-tab=overview]")["aria-current"]).to be_nil
    switch = page.at_css("[data-agent-switch]")                                                         # the people to switch to, the chosen one marked
    expect(switch.css("a[data-agent]").map { |link| link.at_css("span + span").text }).to eq([ "Saida", "Omar", "Owner" ])         # everybody who works the desk, the busiest first
    expect(switch.at_css("a[aria-current=page]").text).to include("Saida")
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
  it "says where the orders ended up and how the confirmed ones are being delivered" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601 }

    rows = page.css("[data-order-outcomes] [data-outcome-row]").to_h { |row| [ row["data-outcome-row"], row["data-count"].to_i ] }
    expect(rows).to eq("delivered" => 1, "returned" => 0, "cancelled" => 1, "in_progress" => 1, "fake" => 0, "not_reached" => 1)      # A1, -, A3, A2, -, A4
    status = page.css("[data-delivery-status] [data-status-row]").to_h { |row| [ row["data-status-row"], row["data-count"].to_i ] }
    expect(status).to include("delivered" => 1, "not_shipped" => 1, "returned" => 0)                                                # the two confirmed orders
    expect(page.at_css("[data-status-delivered]").text.squish).to eq("50,0 %")
    expect(page.at_css("[data-delivery-by-day] [data-by-day]")["data-total"]).to eq("2")
    expect(page.at_css("[data-recovery]").text).to include("Aucun échec de livraison")
    expect(page.at_css("[data-answer-rate]")).to be_present
  end

  it "lists the orders that were recovered after a delivery failure, with the days it took" do
    order = store.orders.find_by!(number: "A1")
    failed_at = 2.days.ago
    OrderEvent.create!(order: order, kind: "status", body: "Status changed from Out for delivery to Unreachable — customer away").update_columns(created_at: failed_at)
    order.update_columns(delivered_at: Time.current)
    sign_in(owner)

    get "/admin/confirmations/analytics", params: { from: 3.days.ago.to_date.iso8601, to: Date.current.iso8601 }

    expect(page.at_css("[data-recovery-rate]").text.squish).to eq("100,0 %")
    expect(page.css("[data-recovery-part]").map { |part| [ part["data-recovery-part"], part["data-count"].to_i ] }).to eq([ [ "recovered", 1 ] ])
    row = page.at_css("[data-recovered=A1]")
    expect(row.text).to include("Client A1", "200 MAD")
    expect(row.text).to include("2 jours")
    expect(response.body).not_to include("Translation missing")                              # no date format without its locale data
    expect(row.text).to match(%r{[0-9]{2}/[0-9]{2}, [0-9]{2}:[0-9]{2}})
  end

  it "shows one agent against the team median, with good and bad gaps coloured" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, agent_id: agent.id }

    expect(page.at_css("[data-agent-header]").text).to include("Saida")
    expect(page.css("[data-agent-metrics] [data-metric]").size).to eq(10)
    confirmation = page.at_css("[data-metric=confirmation_rate]")
    expect(confirmation.at_css("[data-value]").text.squish).to eq("50,0 %")                      # A1 confirmed, A3 cancelled
    expect(confirmation.at_css("[data-median-value]").text.squish).to eq("75,0 %")               # (50 + 100) / 2: Omar confirmed his only order
    expect(confirmation["data-verdict"]).to eq("bad")
    expect(confirmation.at_css("[data-delta]").text.squish).to eq("−25,0 pts")
    expect(page.at_css("[data-agent-count='assignées'] p + p").text.squish).to eq("2")
  end

  it "puts the agents side by side: outcomes, funnel, the table against the median, the recovery" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, view: "agents" }

    expect(page.at_css("[data-analytics-tabs] [data-tab=compare]")["aria-current"]).to eq("page")
    expect(page.css("[data-agents-outcomes] [data-agent-row]").map { |row| row["data-assigned"].to_i }).to eq([ 2, 1, 0 ])   # Saida called A1 and A3, Omar A2, and the owner (who works the desk too) nothing
    expect(page.css("[data-agents-funnel] [data-agent-funnel]").size).to eq(3)
    expect(page.at_css("[data-median-cell=confirmation_rate]").text.squish).to eq("75,0 %")
    cells = page.css("[data-agents-table] [data-agent-row]").to_h { |row| [ row.at_css("a").text.squish.sub(/\A\w{1,2} /, ""), row.at_css("[data-cell=confirmation_rate]")["data-verdict"] ] }
    expect(cells.values).to contain_exactly("bad", "good", "")                                  # 50 % and 100 % against a 75 % median; the owner has no figure
    expect(page.css("[data-agents-recovery] [data-recovery-row]").size).to eq(3)
    expect(page.at_css("[data-overview], [data-kpis=analytics]")).to be_nil                       # the overview is not drawn under the comparison
  end

  it "keeps an agent on her own overview even with view=agents" do
    sign_in(agent)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, view: "agents" }

    expect(page.at_css("[data-agents-table]")).to be_nil
    expect(page.at_css("[data-kpis=analytics]")).to be_present
    expect(page.at_css("[data-agent-metrics]")).to be_present
  end
  it "opens the Agent tab on a list of everybody who works the desk, and a click on a person opens her figures" do
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { from: Date.current.iso8601, to: Date.current.iso8601, view: "agent" }

    expect(page.at_css("[data-analytics-tabs] [data-tab=agent]")["aria-current"]).to eq("page")
    cards = page.css("[data-agent-picker] a[data-agent]")
    expect(cards.map { |card| card.text.squish }.join(" ")).to include("Saida", "Omar")
    expect(cards.map { |card| card["href"] }).to include("/admin/confirmations/analytics?agent_id=#{agent.id}")
    expect(page.at_css("[data-kpis=analytics]")).to be_nil                                              # nothing is drawn before somebody is chosen
    expect(page.at_css("[data-agent-switch]")).to be_nil

    get cards.find { |card| card.text.include?("Saida") }["href"], params: { from: Date.current.iso8601, to: Date.current.iso8601 }
    expect(page.at_css("[data-agent-header]").text).to include("Saida")
  end
end
