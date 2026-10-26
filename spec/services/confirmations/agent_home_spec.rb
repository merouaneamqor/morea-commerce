require "rails_helper"

RSpec.describe Confirmations::AgentHome do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "home-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:agent) { store.users.create!(name: "Lina", email: "lina-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:colleague) { store.users.create!(name: "Ben", email: "ben-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:range) { Time.current.beginning_of_day..Time.current }

  def order
    customer = store.customers.first || store.customers.create!(name: "Buyer", phone: "0612345678", city: "Casablanca")
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Address", total_cents: 101, subtotal_cents: 101, currency: "MAD", status: "new")
  end

  def attempt(user, outcome, handled: nil, at: Time.current)
    confirmation = OrderConfirmation.create!(store: store, order: order)
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: user, outcome: outcome,
      handled_seconds: handled, created_at: at, callback_at: (outcome == "callback" ? 1.hour.from_now : nil))
  end

  def home(user = agent)
    described_class.new(store: store, user: user, range: range)
  end

  it "awards points per outcome for the agent's own attempts" do
    attempt(agent, "confirmed")
    attempt(agent, "callback")
    attempt(agent, "no_answer")
    attempt(colleague, "confirmed")

    expect(home.points).to eq(10 + 3 + 1)
    expect(home.outcome_counts).to eq("confirmed" => 1, "callback" => 1, "no_answer" => 1)
    expect(home.confirmation_rate).to be_within(0.001).of(1.0 / 3)
  end

  it "averages the time spent on the agent's own orders" do
    attempt(agent, "confirmed", handled: 120)
    attempt(agent, "cancelled", handled: 60)
    attempt(agent, "no_answer", handled: nil)
    attempt(colleague, "confirmed", handled: 9_999)

    expect(home.average_handled_seconds).to eq(90)
  end

  it "lists only the orders this agent holds, and only their own recent outcomes" do
    mine = OrderConfirmation.create!(store: store, order: order, assigned_user: agent, claimed_at: 5.minutes.ago)
    OrderConfirmation.create!(store: store, order: order, assigned_user: colleague, claimed_at: 1.minute.ago)
    attempt(colleague, "confirmed")
    attempt(agent, "confirmed")

    expect(home.active_claims).to eq([ mine ])
    expect(home.recent.map(&:user_id)).to all(eq(agent.id))
  end

  it "is empty when the agent has no outcomes today" do
    attempt(agent, "confirmed", at: 3.days.ago)

    expect(home.points).to eq(0)
    expect(home.confirmation_rate).to be_nil
    expect(home.average_handled_seconds).to be_nil
    expect(home.recent).to be_empty
  end
end
