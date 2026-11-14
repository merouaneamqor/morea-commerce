require "rails_helper"

# The "Activité de l'équipe" figures: presence, time worked today, what was done, and the filters.
RSpec.describe Team::Activity do
  let(:store) { Store.create!(slug: "ac-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Moubarak", email: "o-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "s-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let!(:yasmine) { store.users.create!(name: "Yasmine", email: "y-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:now) { Time.current.in_time_zone(DateRange::ZONE).change(hour: 15) }
  let(:activity) { described_class.new(store: store, users: [ owner, saida, yasmine ], now: now) }

  def order_for(agent, number)
    order = store.orders.create!(customer: customer, number: number, status: "delivered", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000, confirmed_at: now - 3.hours, delivered_at: now - 1.hour)
    OrderConfirmation.create!(store: store, order: order, disposition: "confirmed", assigned_user: agent, claimed_at: now - 3.hours)
  end

  before do
    ConfirmationShift.create!(store: store, user: saida, started_at: now - 2.hours, last_seen_at: now - 30.seconds)                       # online, 2 h
    ConfirmationShift.create!(store: store, user: yasmine, started_at: now - 5.hours, ended_at: now - 4.hours, end_reason: "manual")      # offline, 1 h
    confirmation = order_for(saida, "A1")
    2.times { ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: saida, outcome: "no_answer") }
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: saida, outcome: "confirmed")
  end

  it "tells who is online, the time worked, the first and last activity" do
    rows = activity.rows.index_by { |row| row.user.id }
    expect(rows[saida.id]).to have_attributes(online: true, worked_seconds: be_within(2).of(7200), role: :agent)
    expect(rows[yasmine.id]).to have_attributes(online: false, worked_seconds: be_within(2).of(3600), last_seen_at: be_within(1.second).of(now - 4.hours))
    expect(rows[owner.id]).to have_attributes(online: false, worked_seconds: 0, first_at: nil, role: :owner)
    expect(activity.rows.first.user).to eq(saida) # online people first
    expect([ activity.online_count, activity.total ]).to eq([ 1, 3 ])
    expect(activity.worked_total).to be_within(5).of(10_800)
    expect(activity.worked_average).to be_within(3).of(5400) # over the two people who worked
  end

  it "counts what each person did today: calls, confirmations, deliveries" do
    row = activity.rows.find { |candidate| candidate.user == saida }
    expect(row).to have_attributes(calls: 3, confirmed: 1, delivered: 1)
    expect([ activity.calls_total, activity.callers, activity.actions_total ]).to eq([ 3, 1, 5 ])
    expect(activity.rows.find { |candidate| candidate.user == yasmine }).to have_attributes(calls: 0, confirmed: 0, delivered: 0)
  end

  it "filters by presence, role and name" do
    expect(activity.filtered(presence: "online").map(&:user)).to eq([ saida ])
    expect(activity.filtered(presence: "offline").map(&:user)).to contain_exactly(owner, yasmine)
    expect(activity.filtered(role: "owner").map(&:user)).to eq([ owner ])
    expect(activity.filtered(query: "yasm").map(&:user)).to eq([ yasmine ])
    expect(activity.filtered(presence: "all", role: "all").size).to eq(3)
  end

  it "ignores what happened on another day or in another store" do
    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    ConfirmationShift.create!(store: other, user: other.users.create!(name: "X", email: "x-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent"), started_at: now - 1.hour)
    ConfirmationShift.create!(store: store, user: owner, started_at: now - 3.days, ended_at: now - 3.days + 4.hours, end_reason: "manual")
    expect(activity.online_count).to eq(1)
    expect(activity.rows.find { |row| row.user == owner }.worked_seconds).to eq(0)
  end
end
