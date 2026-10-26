require "rails_helper"

RSpec.describe Confirmations::Performance do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "perf-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:other) { Store.create!(slug: "perf-other-#{SecureRandom.hex(5)}", name: "Other desk", currency: "MAD") }
  let(:now) { Time.zone.parse("2026-10-26 12:00") }
  let(:today) { now.beginning_of_day..now }
  let(:ana) { store.users.create!(name: "Ana", email: "ana@example.test", password: password, admin: true, confirmation_role: "supervisor") }
  let(:ben) { store.users.create!(name: "Ben", email: "ben@example.test", password: password, admin: true) }

  def performance(range: today, workspace: store)
    described_class.new(store: workspace, range: range, now: now)
  end

  def order(workspace: store)
    customer = workspace.customers.first || workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 101,
      subtotal_cents: 101, currency: "MAD", status: "new")
  end

  def attempt(agent, outcome, at: now - 1.hour, workspace: store)
    confirmation = OrderConfirmation.create!(store: workspace, order: order(workspace: workspace))
    ConfirmationAttempt.create!(store: workspace, order_confirmation: confirmation, user: agent, outcome: outcome, created_at: at,
      callback_at: (outcome == "callback" ? now + 1.hour : nil))
  end

  def shift(agent, started_at:, ended_at: nil, workspace: store)
    ConfirmationShift.create!(store: workspace, user: agent, started_at: started_at, ended_at: ended_at)
  end

  it "lists only active store admins, with their confirmation role" do
    ana
    ben.update!(status: "suspended")

    rows = performance.rows

    expect(rows.map { |row| row.user.name }).to eq([ "Ana" ])
    expect(rows.first.user.confirmation_role).to eq("supervisor")
  end

  it "counts attempts per agent inside the range only" do
    attempt(ana, "confirmed", at: now - 1.hour)
    attempt(ana, "cancelled", at: now - 2.hours)
    attempt(ana, "confirmed", at: now - 3.days)

    figures = performance.rows.find { |row| row.user == ana }.figures

    expect(figures.attempts).to eq(2)
    expect(figures.confirmed).to eq(1)
    expect(figures.cancelled).to eq(1)
    expect(figures.confirmation_rate).to eq(0.5)
  end

  it "ignores attempts and shifts from another workspace" do
    foreign_agent = other.users.create!(email: "foreign@example.test", password: password, admin: true)
    attempt(foreign_agent, "confirmed", workspace: other)
    shift(foreign_agent, started_at: now - 2.hours, workspace: other)

    expect(performance.totals.attempts).to eq(0)
    expect(performance.totals.worked_seconds).to eq(0)
    expect(performance.rows.map { |row| row.user.id }).not_to include(foreign_agent.id)
  end

  it "clips shifts to the range and runs open shifts until now" do
    shift(ana, started_at: now.beginning_of_day - 2.hours, ended_at: now.beginning_of_day + 1.hour)
    shift(ben, started_at: now - 30.minutes)

    rows = performance.rows

    expect(rows.find { |row| row.user == ana }.figures.worked_seconds).to eq(1.hour.to_i)
    expect(rows.find { |row| row.user == ben }.figures.worked_seconds).to eq(30.minutes.to_i)
    expect(rows.find { |row| row.user == ben }.on_shift).to be(true)
    expect(performance.agents_on_shift).to eq(1)
  end

  it "derives confirmations per worked hour" do
    shift(ana, started_at: now - 2.hours, ended_at: now)
    attempt(ana, "confirmed", at: now - 30.minutes)
    attempt(ana, "confirmed", at: now - 20.minutes)
    attempt(ana, "no_answer", at: now - 10.minutes)

    figures = performance.rows.find { |row| row.user == ana }.figures

    expect(figures.confirmations_per_hour).to eq(1.0)
    expect(performance.totals.confirmations_per_hour).to eq(1.0)
  end

  it "reports no rate or per-hour figure when there is nothing to divide by" do
    attempt(ana, "confirmed", at: now - 1.hour)

    expect(performance.totals.confirmation_rate).to eq(1.0)
    expect(performance.totals.confirmations_per_hour).to be_nil
    expect(performance(range: now.beginning_of_day - 10.days..now.beginning_of_day - 9.days).totals.confirmation_rate).to be_nil
  end
end
