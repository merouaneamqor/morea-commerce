require "rails_helper"
require "nokogiri"

# An agent who leaves the page or the phone is not counted any more, and the owner sees when each agent came and went.
RSpec.describe "Agent presence", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "pr-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "closes a shift with no sign of life at the last time the agent was seen, and keeps a shift that is still beating" do
    gone = ConfirmationShift.create!(store: store, user: saida, started_at: 2.hours.ago, last_seen_at: 30.minutes.ago)
    here = ConfirmationShift.create!(store: store, user: omar, started_at: 2.hours.ago, last_seen_at: 30.seconds.ago)

    Confirmations::Shifts.close_stale!

    expect(gone.reload).to have_attributes(end_reason: "inactive", ended_at: be_within(1.second).of(30.minutes.ago))
    expect(here.reload.ended_at).to be_nil
    expect(gone.seconds_within(3.hours.ago..Time.current)).to be_within(2).of(90.minutes.to_i)
  end

  it "gives the agent's held orders back when the shift is closed for inactivity" do
    customer = store.customers.create!(name: "Client", phone: "0612345678")
    order = store.orders.create!(customer: customer, number: "H1", status: "new", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    OrderConfirmation.create!(store: store, order: order, disposition: "pending", assigned_user: saida, claimed_at: 10.minutes.ago)
    ConfirmationShift.create!(store: store, user: saida, started_at: 1.hour.ago, last_seen_at: 20.minutes.ago)

    Confirmations::Shifts.close_stale!

    expect(order.order_confirmation.reload.assigned_user_id).to be_nil
  end

  it "answers the heartbeat with whether the shift is still open, and refreshes the last sign of life" do
    sign_in(saida)
    post heartbeat_admin_confirmations_path
    expect(JSON.parse(response.body)).to eq("open" => false)

    shift = ConfirmationShift.create!(store: store, user: saida, started_at: 1.hour.ago, last_seen_at: 2.minutes.ago)
    post heartbeat_admin_confirmations_path
    expect(JSON.parse(response.body)).to eq("open" => true)
    expect(shift.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
  end

  it "does not revive a shift the agent abandoned: the late beat closes it at the last sign of life" do
    sign_in(saida)
    shift = ConfirmationShift.create!(store: store, user: saida, started_at: 2.hours.ago, last_seen_at: 40.minutes.ago)
    post heartbeat_admin_confirmations_path

    expect(JSON.parse(response.body)).to eq("open" => false)
    expect(shift.reload).to have_attributes(end_reason: "inactive", ended_at: be_within(1.second).of(40.minutes.ago))
  end

  it "asks an agent who is not on shift to clock in when they open the site, and stops once they are on shift; never asks the owner" do
    sign_in(saida)
    get admin_my_stats_path
    prompt = page.at_css("[data-clock-in-prompt]")
    expect(prompt).to be_present
    expect(prompt.at_css("form")["action"]).to eq(clock_in_admin_confirmations_path)
    expect(prompt.at_css("[data-action='clock-in-prompt#dismiss']")).to be_present

    post clock_in_admin_confirmations_path
    get admin_my_stats_path
    expect(page.at_css("[data-clock-in-prompt]")).to be_nil

    delete admin_logout_path rescue nil
    sign_in(owner)
    get "/admin/orders"
    expect(page.at_css("[data-clock-in-prompt]")).to be_nil
  end

  it "only puts the presence beat on the pages of an agent who is on shift" do
    sign_in(saida)
    get admin_my_stats_path
    expect(page.at_css("[data-presence]")).to be_nil

    post clock_in_admin_confirmations_path
    get admin_my_stats_path
    expect(page.at_css("[data-presence]")["data-presence-url-value"]).to eq(heartbeat_admin_confirmations_path)
  end

  it "lists every agent's arrivals and departures for the owner, and keeps agents out" do
    ConfirmationShift.create!(store: store, user: saida, started_at: 3.hours.ago, ended_at: 2.hours.ago, end_reason: "manual", last_seen_at: 2.hours.ago)
    ConfirmationShift.create!(store: store, user: saida, started_at: 90.minutes.ago, ended_at: 60.minutes.ago, end_reason: "inactive", last_seen_at: 60.minutes.ago)
    ConfirmationShift.create!(store: store, user: omar, started_at: 20.minutes.ago, last_seen_at: Time.current)

    sign_in(owner)
    get attendance_admin_confirmations_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-agent-row='#{saida.id}']")["data-worked"].to_i).to be_between(5390, 5410)
    expect(page.at_css("[data-agent-row='#{omar.id}'] [data-on-shift]")).to be_present
    expect(page.css("[data-shift]").map { |row| row["data-ended"] }).to contain_exactly("manual", "inactive", "open")
    get attendance_admin_confirmations_path, params: { agent_id: omar.id }
    expect(page.css("[data-shift]").size).to eq(1)

    delete admin_logout_path rescue nil
    sign_in(saida)
    get attendance_admin_confirmations_path
    expect(response).to have_http_status(:forbidden)
  end
end
