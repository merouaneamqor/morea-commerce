require "rails_helper"

RSpec.describe Confirmations::AgentComparison do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { ActiveSupport::TimeZone[DateRange::ZONE] }
  let(:now) { zone.local(2026, 11, 12, 12, 0) }
  let(:store) { Store.create!(slug: "ac-#{SecureRandom.hex(5)}", name: "Compare", currency: "MAD") }
  let(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:idle) { store.users.create!(name: "Idle", email: "idle-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:range) { DateRange.from_params({ from: "2026-11-01", to: "2026-11-12" }, today: Date.new(2026, 11, 12)) }
  let(:comparison) { described_class.new(store: store, from: range.from, to: range.to, range: range.time_range, now: now) }

  def make(number, created, status: "new", confirmed: nil, delivered: nil)
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.update_columns(status: status, created_at: created, confirmed_at: confirmed, delivered_at: delivered)
    record
  end

  def call(order, outcome, at, user)
    confirmation = OrderConfirmation.find_or_create_by!(store: store, order: order) { |row| row.disposition = "pending" }
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: user, outcome: outcome).update_columns(created_at: at)
  end

  # Saida: A (confirmed, delivered), B (cancelled).   Omar: C (confirmed, not delivered), D (no answer).   Idle: nothing.
  before do
    travel_to(now)
    idle
    a = make("A", zone.local(2026, 11, 10, 9, 0), status: "delivered", confirmed: zone.local(2026, 11, 10, 9, 10), delivered: zone.local(2026, 11, 11, 15, 0))
    b = make("B", zone.local(2026, 11, 10, 10, 0), status: "cancelled")
    c = make("C", zone.local(2026, 11, 10, 11, 0), status: "in_transit", confirmed: zone.local(2026, 11, 10, 11, 20))
    d = make("D", zone.local(2026, 11, 11, 8, 0))
    call(a, "confirmed", zone.local(2026, 11, 10, 9, 10), saida)
    call(b, "cancelled", zone.local(2026, 11, 10, 10, 10), saida)
    call(c, "confirmed", zone.local(2026, 11, 10, 11, 20), omar)
    call(d, "no_answer", zone.local(2026, 11, 11, 8, 20), omar)
  end

  after { travel_back }

  it "lists everybody who works the desk, the busiest first; someone with no order keeps a row with empty figures" do
    expect(comparison.rows.map { |row| row.user.name }).to eq([ "Saida", "Omar", "Idle" ])
    idle_row = comparison.rows.last
    expect(idle_row.analytics.assigned).to eq(0)
    expect(idle_row.metrics.values).to all(be_nil)                                  # no order: no figure, and no weight in the median
    saida_row = comparison.rows.find { |row| row.user == saida }
    expect(saida_row.analytics.assigned).to eq(2)
    expect(saida_row.metrics).to include(delivered_per_100: 50.0, confirmation_rate: 50.0, delivery_rate: 100.0)       # A of A + B; A of 1 confirmed
    omar_row = comparison.rows.find { |row| row.user == omar }
    expect(omar_row.metrics).to include(delivered_per_100: 0.0, confirmation_rate: 50.0, delivery_rate: 0.0)           # C confirmed, not delivered
  end

  it "takes the team median over the agents (the mean of the two middle values with two agents)" do
    expect(comparison.median(:delivered_per_100)).to eq(25.0)                       # (50 + 0) / 2
    expect(comparison.median(:confirmation_rate)).to eq(50.0)
    expect(comparison.median(:perseverance)).to eq(0.0)                             # only Omar had an unanswered first call, and D was not called again
  end

  it "says whether a value is good or bad against the median, depending on the direction of the figure" do
    expect(comparison.verdict(:delivered_per_100, 50.0)).to eq(:good)               # higher is better
    expect(comparison.verdict(:delivered_per_100, 0.0)).to eq(:bad)
    expect(comparison.verdict(:return_rate, 10.0)).to eq(:bad)                      # the median is 0 and a lower rate is better
    expect(comparison.verdict(:confirmation_rate, 50.0)).to be_nil                  # equal to the median: no colour
    expect(comparison.verdict(:calls_per_order, 3.0)).to be_nil                     # neither direction is good
    expect(comparison.verdict(:delivered_per_100, nil)).to be_nil
  end
end
