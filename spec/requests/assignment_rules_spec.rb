require "rails_helper"
require "nokogiri"

RSpec.describe "Attribution rules page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "rp-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def names = page.css("[data-rules-table] [data-rule]").map { |row| row.at_css("td:nth-child(2) p").text.squish }

  def rule!(name, agents: [ saida, omar ], percents: nil, **attrs)
    rule = store.assignment_rules.new({ name: name, distribution: (percents ? "percent" : "equal") }.merge(attrs))
    agents.each_with_index { |agent, index| rule.assignment_rule_agents.build(user: agent, percent: percents&.at(index)) }
    rule.save!
    rule
  end

  def form_params(overrides = {})
    { assignment_rule: { name: "Grosses commandes", description: "Pour les meilleurs", distribution: "equal", agent_ids: [ saida.id, omar.id ], timeout_minutes: "30", transfer_on_timeout: "1", active: "1",
                         min_amount: "", max_amount: "", sources_mode: "all" }.merge(overrides) }
  end

  it "shows an empty page with the explanation, the four figures and the button to create a rule" do
    sign_in(owner)
    get "/admin/confirmations/rules"

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to include("Règles d'attribution")
    expect(page.at_css("[data-no-rules]")).to be_present
    expect(page.at_css("[data-rules-info]").text).to include("première règle active", "30 minutes")
    expect(page.css("[data-rules-stats] [data-value]").map { |value| value.text.squish }).to eq([ "0", "0", "0", "Inactive" ])
    expect(page.at_css("[data-new-rule]")["data-turbo-frame"]).to eq("order-modal")
    expect(page.at_css("[data-subnav-item=rules]")["aria-current"]).to eq("page")
  end

  it "lists the rules in priority order with their conditions, agents, split, delay and switch" do
    first = rule!("VIP", min_amount_cents: 50_000, agents: [ saida ])
    rule!("Général", percents: [ 70, 30 ], timeout_minutes: 45, active: false)
    first.update!(sources: [ "manual" ])
    sign_in(owner)

    get "/admin/confirmations/rules"

    expect(names).to eq(%w[VIP Général])
    vip, general = page.css("[data-rules-table] [data-rule]")
    expect(vip.at_css("[data-conditions]").text.squish).to include("Montant ≥ 500 MAD", "1 source")
    expect(vip.at_css("[data-agents]").text.squish).to eq("Saida")
    expect(vip.at_css("[data-distribution]")["data-distribution"]).to eq("equal")
    expect(vip["data-active"]).to eq("true")
    expect(general.at_css("[data-agents]").text.squish).to include("Saida · 70 %", "Omar · 30 %")
    expect(general.at_css("[data-timeout]")["data-timeout"]).to eq("45")
    expect(general["data-active"]).to eq("false")
    expect(page.css("[data-rules-stats] [data-value]").map { |value| value.text.squish }).to eq([ "2", "1", "1", "Active" ])
  end

  it "creates a rule that splits equally over the chosen agents, with a minimum amount typed in MAD" do
    sign_in(owner)

    post "/admin/confirmations/rules", params: form_params(min_amount: "500", max_amount: "1 000".delete(" "))

    expect(response).to redirect_to("/admin/confirmations/rules")
    rule = store.assignment_rules.sole
    expect(rule).to have_attributes(name: "Grosses commandes", distribution: "equal", min_amount_cents: 50_000, max_amount_cents: 100_000, timeout_minutes: 30, transfer_on_timeout: true, active: true, sources: [], position: 1)
    expect(rule.assignment_rule_agents.map { |row| [ row.user_id, row.percent ] }).to contain_exactly([ saida.id, nil ], [ omar.id, nil ])
    follow_redirect!
    expect(response.body).to include("Règle créée.")
  end

  it "creates a rule that splits by percentage and limited to chosen sources" do
    sign_in(owner)

    post "/admin/confirmations/rules", params: form_params(distribution: "percent", percents: { saida.id.to_s => "70", omar.id.to_s => "30" }, sources_mode: "chosen", sources: [ "manual", "999" ])

    rule = store.assignment_rules.sole
    expect(rule.assignment_rule_agents.to_h { |row| [ row.user_id, row.percent ] }).to eq(saida.id => 70, omar.id => 30)
    expect(rule.sources).to eq([ "manual" ])                                                 # an unknown source is dropped
  end

  it "keeps the window open with the reason when the percentages do not add up, nobody is chosen, or an amount is wrong" do
    sign_in(owner)

    post "/admin/confirmations/rules", params: form_params(distribution: "percent", percents: { saida.id.to_s => "60", omar.id.to_s => "30" }), headers: { "Turbo-Frame" => "order-modal" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css("[data-rule-errors]").text).to include("must add up to 100 % (now 90 %)")
    expect(page.at_css("turbo-frame#order-modal [data-narrow]")).to be_present
    expect(page.at_css("input[name='assignment_rule[name]']")["value"]).to eq("Grosses commandes")            # what was typed is still there

    post "/admin/confirmations/rules", params: form_params(agent_ids: [])
    expect(page.at_css("[data-rule-errors]").text).to include("Choose at least one agent")

    post "/admin/confirmations/rules", params: form_params(min_amount: "abc")
    expect(page.at_css("[data-rule-errors]").text).to include("valid amount")

    post "/admin/confirmations/rules", params: form_params(min_amount: "900", max_amount: "100")
    expect(page.at_css("[data-rule-errors]").text).to include("must not be below the minimum")

    post "/admin/confirmations/rules", params: form_params(timeout_minutes: "2")
    expect(page.at_css("[data-rule-errors]").text).to include("Timeout minutes")
    expect(store.assignment_rules.count).to eq(0)
  end

  it "ignores agents that are not agents of this store" do
    other = Store.create!(slug: "rp-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    stranger = other.users.create!(name: "Stranger", email: "x-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")
    sign_in(owner)

    post "/admin/confirmations/rules", params: form_params(agent_ids: [ saida.id, stranger.id, owner.id ])

    expect(store.assignment_rules.sole.agents).to eq([ saida ])
  end

  it "opens the form in the glass window for a frame request and as a page otherwise" do
    rule = rule!("VIP")
    sign_in(owner)

    get "/admin/confirmations/rules/new", headers: { "Turbo-Frame" => "order-modal" }
    expect(response.body).not_to include("data-seller-shell")
    expect(page.at_css("turbo-frame#order-modal [data-order-modal-panel][data-narrow]")).to be_present
    expect(page.css("input[name='assignment_rule[agent_ids][]']").map { |box| box["value"].to_i }).to contain_exactly(saida.id, omar.id)
    expect(page.at_css("input[name='assignment_rule[timeout_minutes]']")["value"]).to eq("30")

    get "/admin/confirmations/rules/#{rule.id}/edit"
    expect(page.at_css("[data-seller-shell]")).to be_present
    expect(page.at_css("input[name='assignment_rule[name]']")["value"]).to eq("VIP")
    expect(page.css("input[name='assignment_rule[agent_ids][]'][checked]").size).to eq(2)
  end

  it "edits a rule: another split, other agents, a longer delay; and forgets the percentages when it goes back to equal parts" do
    rule = rule!("VIP", percents: [ 60, 40 ])
    sign_in(owner)

    patch "/admin/confirmations/rules/#{rule.id}", params: form_params(name: "VIP bis", distribution: "equal", agent_ids: [ omar.id ], timeout_minutes: "45", transfer_on_timeout: "0")

    expect(response).to redirect_to("/admin/confirmations/rules")
    expect(rule.reload).to have_attributes(name: "VIP bis", distribution: "equal", timeout_minutes: 45, transfer_on_timeout: false)
    expect(rule.assignment_rule_agents.map { |row| [ row.user_id, row.percent ] }).to eq([ [ omar.id, nil ] ])
  end

  it "switches a rule on and off" do
    rule = rule!("VIP")
    sign_in(owner)

    patch "/admin/confirmations/rules/#{rule.id}/toggle"
    expect(rule.reload.active).to be(false)
    follow_redirect!
    expect(response.body).to include("Règle « VIP » désactivée.")

    patch "/admin/confirmations/rules/#{rule.id}/toggle"
    expect(rule.reload.active).to be(true)
  end

  it "moves a rule up or down the priority, and does nothing at the ends" do
    a = rule!("A")
    b = rule!("B")
    c = rule!("C")
    sign_in(owner)

    patch "/admin/confirmations/rules/#{c.id}/move", params: { direction: "up" }
    expect(store.assignment_rules.reload.map(&:name)).to eq(%w[A C B])
    patch "/admin/confirmations/rules/#{a.id}/move", params: { direction: "up" }
    expect(store.assignment_rules.reload.map(&:name)).to eq(%w[A C B])
    patch "/admin/confirmations/rules/#{b.id}/move", params: { direction: "down" }
    expect(store.assignment_rules.reload.map(&:name)).to eq(%w[A C B])
    patch "/admin/confirmations/rules/#{a.id}/move", params: { direction: "down" }
    expect(store.assignment_rules.reload.map(&:name)).to eq(%w[C A B])
    expect(store.assignment_rules.reload.map(&:position)).to eq([ 1, 2, 3 ])
  end

  it "deletes a rule and leaves the orders it attributed with their agent" do
    rule = rule!("VIP")
    customer = store.customers.create!(name: "Client", phone: "0612345678")
    order = store.orders.create!(customer: customer, number: "R1", status: "new", currency: "MAD", customer_name: "C", customer_phone: "0612345678", customer_city: "Fès", customer_address: "a", subtotal_cents: 100, total_cents: 100)
    confirmation = OrderConfirmation.create!(store: store, order: order, attributed_user: saida, assignment_rule: rule, attributed_at: 1.minute.ago)
    sign_in(owner)

    delete "/admin/confirmations/rules/#{rule.id}"

    expect(response).to redirect_to("/admin/confirmations/rules")
    expect(store.assignment_rules.count).to eq(0)
    expect(confirmation.reload).to have_attributes(attributed_user_id: saida.id, assignment_rule_id: nil)
  end

  it "is closed to the confirmation agents and to another store's rules" do
    rule = rule!("VIP")
    other = Store.create!(slug: "rp-o2-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    foreign = other.assignment_rules.new(name: "Foreign", distribution: "equal")
    foreign.assignment_rule_agents.build(user: other.users.create!(name: "X", email: "x2-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent"))
    foreign.save!

    sign_in(saida)
    get "/admin/confirmations/rules"
    expect(response).not_to have_http_status(:ok)
    post "/admin/confirmations/rules", params: form_params
    expect(response).not_to have_http_status(:ok)
    patch "/admin/confirmations/rules/#{rule.id}/toggle"
    expect(rule.reload.active).to be(true)
    expect(store.assignment_rules.count).to eq(1)

    sign_in(owner)
    patch "/admin/confirmations/rules/#{foreign.id}/toggle"
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.active).to be(true)
  end
end
