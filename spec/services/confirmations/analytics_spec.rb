require "rails_helper"

RSpec.describe Confirmations::Analytics do
  include ActiveSupport::Testing::TimeHelpers

  # Times are written on the shop clock (DateRange::ZONE), whatever the offset of that zone is in November.
  let(:zone) { ActiveSupport::TimeZone[DateRange::ZONE] }
  let(:now) { zone.local(2026, 11, 12, 12, 0) }
  let(:store) { Store.create!(slug: "an-#{SecureRandom.hex(5)}", name: "Analytics", currency: "MAD") }
  let(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:range) { DateRange.from_params({ from: "2026-11-01", to: "2026-11-12" }, today: Date.new(2026, 11, 12)) }

  def analytics(agent: nil)
    described_class.new(store: store, from: range.from, to: range.to, range: range.time_range, agent: agent, now: now)
  end

  def make(number, created, status: "new", confirmed: nil, shipped: nil, delivered: nil, cancelled: nil, reason: nil)
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.update_columns(status: status, created_at: created, confirmed_at: confirmed, shipped_at: shipped, delivered_at: delivered, cancelled_at: cancelled, cancel_reason: reason)
    record
  end

  def call(order, outcome, at, user)
    confirmation = OrderConfirmation.find_or_create_by!(store: store, order: order) { |row| row.disposition = "pending" }
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: user, outcome: outcome).tap { |attempt| attempt.update_columns(created_at: at) }
  end

  # Five orders created on 10 and 11 Nov, and one cancelled order created before the range.
  #   O1 10 Nov 09:00  called at 09:10 (Saida) confirmed, shipped, delivered
  #   O2 10 Nov 09:30  called at 10:30 no answer (Omar), at 13:30 confirmed (Omar), shipped
  #   O3 10 Nov 10:00  called at 10:05 cancelled (Saida): "Client change d'avis"
  #   O4 11 Nov 08:00  called at 08:10 no answer (Omar)
  #   O5 11 Nov 08:30  never called, still new
  #   O6 created 20 Oct, cancelled 5 Nov, no reason
  before do
    travel_to(now)
    o1 = make("O1", zone.local(2026, 11, 10, 9, 0), status: "delivered", confirmed: zone.local(2026, 11, 10, 9, 10), shipped: zone.local(2026, 11, 10, 15, 0), delivered: zone.local(2026, 11, 11, 15, 0))
    o2 = make("O2", zone.local(2026, 11, 10, 9, 30), status: "in_transit", confirmed: zone.local(2026, 11, 10, 13, 30), shipped: zone.local(2026, 11, 11, 9, 0))
    o3 = make("O3", zone.local(2026, 11, 10, 10, 0), status: "cancelled", cancelled: zone.local(2026, 11, 10, 10, 5), reason: "Client change d'avis")
    o4 = make("O4", zone.local(2026, 11, 11, 8, 0))
    make("O5", zone.local(2026, 11, 11, 8, 30))
    make("O6", zone.local(2026, 10, 20, 9, 0), status: "cancelled", cancelled: zone.local(2026, 11, 5, 9, 0))
    call(o1, "confirmed", zone.local(2026, 11, 10, 9, 10), saida)
    call(o2, "no_answer", zone.local(2026, 11, 10, 10, 30), omar)
    call(o2, "confirmed", zone.local(2026, 11, 10, 13, 30), omar)
    call(o3, "cancelled", zone.local(2026, 11, 10, 10, 5), saida)
    call(o4, "no_answer", zone.local(2026, 11, 11, 8, 10), omar)
  end

  after { travel_back }

  it "counts the funnel of the orders created in the range" do
    expect(analytics).to have_attributes(assigned: 5, reached: 3, confirmed: 2, shipped: 2, delivered: 1)   # O6 is before the range
    expect(analytics.funnel.map { |key, count, step| [ key, count, step ] }).to eq([
      [ :assigned, 5, nil ], [ :reached, 3, 60.0 ], [ :confirmed, 2, 66.7 ], [ :shipped, 2, 100.0 ], [ :delivered, 1, 50.0 ]
    ])
  end

  it "computes the three rates with one decimal, and nothing (nil) when there is nothing to divide by" do
    expect(analytics).to have_attributes(confirmation_rate: 40.0, delivery_rate: 50.0, delivered_per_100: 20.0)  # 2/5, 1/2, 1/5
    empty = described_class.new(store: store, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 2), range: zone.local(2026, 10, 1)..zone.local(2026, 10, 2), now: now)
    expect(empty).to have_attributes(assigned: 0, confirmation_rate: nil, delivery_rate: nil, median_first_call_seconds: nil)
  end

  it "lists every day of the range, with the rates of the day and the newest days as provisional" do
    days = analytics.daily
    expect(days.size).to eq(12)
    tenth = days.find { |day| day[:date] == Date.new(2026, 11, 10) }
    expect(tenth).to include(created: 3, confirmed: 2, unconfirmed: 1, delivered: 1, confirmation_rate: 66.7, delivery_rate: 50.0, delivered_per_100: 33.3)
    eleventh = days.find { |day| day[:date] == Date.new(2026, 11, 11) }
    expect(eleventh).to include(created: 2, confirmed: 0, confirmation_rate: 0.0, delivery_rate: nil)           # no confirmed order: no delivery rate
    expect(days.select { |day| day[:provisional] }.map { |day| day[:date] }.first).to eq(Date.new(2026, 11, 6))     # the last 7 days
    expect(days.first[:provisional]).to be(false)
  end

  it "measures the first call: median wait and the confirmation rate by wait" do
    expect(analytics.first_call_seconds.sort).to eq([ 300, 600, 600, 3600 ])
    expect(analytics.median_first_call_seconds).to eq(600)                                                        # (600 + 600) / 2
    speed = analytics.first_call_speed.to_h { |bucket| [ bucket[:key], bucket.slice(:orders, :confirmed, :rate) ] }
    expect(speed[:lt15]).to eq(orders: 3, confirmed: 1, rate: 33.3)                                               # O1 10 min, O3 5 min, O4 10 min
    expect(speed[:lt3h]).to eq(orders: 1, confirmed: 1, rate: 100.0)                                              # O2 waited exactly 1 h
    expect(speed[:lt60]).to eq(orders: 0, confirmed: 0, rate: nil)
  end

  it "describes the live waiting queue: new orders with no call, by age" do
    queue = analytics.queue
    expect(queue[:total]).to eq(1)                                                                                # O5 only: O4 was called
    expect(queue[:oldest_seconds]).to eq(99_000)                                                                  # 11 Nov 08:30 to 12 Nov 12:00 = 27 h 30
    expect(queue[:buckets].to_h { |bucket| [ bucket[:key], bucket[:count] ] }).to eq(lt1h: 0, lt6h: 0, lt24h: 0, gt24h: 1)
  end

  it "finds the call that confirmed each confirmed order" do
    at_call = analytics.confirmed_at_call
    expect(at_call[:total]).to eq(2)
    expect(at_call[:buckets].map { |bucket| [ bucket[:position], bucket[:count], bucket[:percent] ] }).to eq([ [ 1, 1, 50.0 ], [ 2, 1, 50.0 ], [ 3, 0, 0.0 ], [ 4, 0, 0.0 ], [ 5, 0, 0.0 ] ])
  end

  it "breaks the calls of the range down by result" do
    results = analytics.call_results
    expect(results[:total]).to eq(5)
    expect(results[:outcomes].to_h { |row| [ row[:outcome], [ row[:count], row[:percent] ] ] }).to include(
      "confirmed" => [ 2, 40.0 ], "no_answer" => [ 2, 40.0 ], "cancelled" => [ 1, 20.0 ], "callback" => [ 0, 0.0 ], "wrong_number" => [ 0, 0.0 ]
    )
  end

  it "groups the reasons of the orders cancelled in the range, blank ones apart" do
    reasons = analytics.cancel_reasons
    expect(reasons).to include(total: 2, blank: 1, blank_percent: 50.0)
    expect(reasons[:rows].map { |row| [ row[:reason], row[:count], row[:percent] ] }).to eq([ [ "", 1, 50.0 ], [ "client change d'avis", 1, 50.0 ] ])
  end

  it "counts new orders and calls by hour of the shop's clock" do
    hourly = analytics.hourly
    expect(hourly[:new_orders].each_with_index.reject { |count, _| count.zero? }).to eq([ [ 2, 8 ], [ 2, 9 ], [ 1, 10 ] ])       # O4 O5 at 08h, O1 O2 at 09h, O3 at 10h
    expect(hourly[:calls].each_with_index.reject { |count, _| count.zero? }).to eq([ [ 1, 8 ], [ 1, 9 ], [ 2, 10 ], [ 1, 13 ] ])
  end

  it "builds the answer heat map by weekday (Monday first) and hour, and names no slot with too few calls" do
    map = analytics.answer_heatmap
    expect(map.size).to eq(7)
    expect(map.first.size).to eq(24)
    expect(map[1][9]).to eq(calls: 1, answered: 1, rate: 100.0)                                                    # Tuesday 09:00: O1 answered
    expect(map[1][10]).to eq(calls: 2, answered: 1, rate: 50.0)                                                   # Tuesday 10:00: O2 no answer, O3 answered
    expect(map[2][8]).to eq(calls: 1, answered: 0, rate: 0.0)                                                     # Wednesday 08:00: O4 no answer
    expect(map[0][0]).to eq(calls: 0, answered: 0, rate: nil)
    expect(analytics.answer_slots).to eq(best: nil, worst: nil)                                                   # every slot has fewer than 5 calls
  end

  it "looks at one agent: only the orders she called and her own calls" do
    only = analytics(agent: saida)

    expect(only).to have_attributes(assigned: 2, reached: 2, confirmed: 1, confirmation_rate: 50.0)             # O1 and O3
    expect(only.call_results[:total]).to eq(2)
    expect(only.call_results[:outcomes].to_h { |row| [ row[:outcome], row[:count] ] }).to include("confirmed" => 1, "cancelled" => 1, "no_answer" => 0)
  end
end
