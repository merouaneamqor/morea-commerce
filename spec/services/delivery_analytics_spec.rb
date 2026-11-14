require "rails_helper"

# The delivery management figures, checked against orders whose numbers are worked out by hand.
RSpec.describe DeliveryAnalytics do
  let(:store) { Store.create!(slug: "da-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:now) { Time.current }
  let(:range) { (now - 10.days)...(now + 1.day) }
  let(:analytics) { described_class.new(store: store, range: range, now: now) }

  def parcel(number, status, city:, total:, **columns)
    order = store.orders.create!(customer: customer, number: number, status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: city, customer_address: "Rue 1", subtotal_cents: total, total_cents: total)
    order.update_columns({ delivery_fee_cents: nil, return_fee_cents: nil, collected_cents: nil, collected_at: nil, sendit_code: nil }.merge(columns))
    order
  end

  before do
    parcel("A", "delivered", city: "Fès", total: 20_000, sendit_code: "S1", shipped_at: now - 4.days, delivered_at: now - 2.days, delivery_fee_cents: 3_500, collected_cents: 20_000, collected_at: now - 1.day)
    parcel("B", "delivered", city: "Fès", total: 30_000, sendit_code: "S2", shipped_at: now - 5.days, delivered_at: now - 1.day, delivery_fee_cents: 3_500)
    parcel("C", "returned", city: "Sale", total: 25_000, sendit_code: "S3", sendit_return_status: "RETURN_SELLER", return_fee_cents: 1_500)
    parcel("D", "returned", city: "Sale", total: 40_000, sendit_code: "S4", sendit_return_status: "RETURN_WAREHOUSE")
    parcel("E", "in_transit", city: "Rabat", total: 10_000, sendit_code: "S5", sendit_synced_at: now - 5.days)
    parcel("F", "unreachable", city: "Rabat", total: 15_000, shipped_at: now - 3.days)
    parcel("J", "awaiting_pickup", city: "Agadir", total: 12_000, sendit_code: "S6")
    parcel("G", "confirmed", city: "Fès", total: 9_000)   # not a parcel yet
    parcel("H", "new", city: "Fès", total: 9_000)         # not a parcel yet
    parcel("I", "cancelled", city: "Fès", total: 9_000)   # not a parcel
  end

  it "counts the parcels (what left for delivery) and the rates" do
    expect(analytics.total).to eq(7)
    expect([ analytics.delivered_count, analytics.returned_count, analytics.returning_count ]).to eq([ 2, 2, 1 ])
    expect(analytics.delivery_rate).to eq(28.57)
    expect(analytics.return_rate).to eq(28.57)
    expect(analytics.stages.transform_values { |stage| stage[:count] }).to eq("delivered" => 2, "returned" => 1, "return_in_progress" => 1, "waiting" => 1, "failed" => 1, "in_transit" => 1, "out_for_delivery" => 0)
  end

  it "measures the delivery time of the delivered parcels" do
    expect(analytics.average_days).to eq(3.0)   # 2 days and 4 days
    expect(analytics.fast_share).to eq(50.0)    # one of the two within two days
    expect(analytics.delay_buckets.to_h { |bucket| [ bucket[:key], bucket[:count] ] }).to eq("lt1" => 0, "1_2" => 0, "2_3" => 1, "3_5" => 1, "5plus" => 0)
  end

  it "calculates the cost of delivering and the cash flow" do
    expect([ analytics.delivery_fees, analytics.return_fees, analytics.fees ]).to eq([ 7_000, 1_500, 8_500 ])
    expect(analytics.cost_per_delivered).to eq(4_250.0)
    expect(analytics.average_order).to eq(25_000.0)
    expect(analytics.cost_share).to eq(17.0)
    expect(analytics.missing_fees).to eq(1)                      # the returned parcel D has no return fee yet
    expect([ analytics.cod_total, analytics.paid_out, analytics.due, analytics.after_fees ]).to eq([ 50_000, 20_000, 30_000, 41_500 ])
    expect(analytics.paid_share).to eq(40.0)
  end

  it "groups by city, source and order value" do
    cities = analytics.cities
    expect(cities.map { |city| [ city.key, city.parcels ] }).to eq([ [ "Fès", 2 ], [ "Rabat", 2 ], [ "Sale", 2 ], [ "Agadir", 1 ] ])
    expect(cities.first).to have_attributes(delivered: 2, fees: 7_000, days: 3.0)
    expect(cities.find { |city| city.key == "Sale" }).to have_attributes(returned: 2, returning: 1, fees: 1_500)
    expect(analytics.sources.map { |source| [ source.key, source.parcels ] }).to eq([ [ "manual", 7 ] ])
    expect(analytics.value_bands.to_h { |band| [ band[:key], [ band[:parcels], band[:delivered] ] ] }).to eq("lt200" => [ 3, 0 ], "200_299" => [ 2, 1 ], "300_449" => [ 2, 1 ], "450plus" => [ 0, 0 ])
  end

  it "lists what needs attention and why parcels fail" do
    expect(analytics.problems).to eq(failed: { count: 1, cod: 15_000 }, returning: { count: 1, cod: 40_000 }, stuck: { count: 1, cod: 10_000 })
    expect(analytics.failure_causes.map { |cause| [ cause[:key], cause[:count], cause[:share] ] }).to eq([ [ "returned", 2, 66.67 ], [ "unreachable", 1, 33.33 ] ])
  end

  it "gives one entry per day, with a rate only when enough parcels were sent" do
    expect(analytics.daily.sum { |day| day[:parcels] }).to eq(7)
    expect(analytics.daily.size).to eq(12) # ten days back to tomorrow
    expect(analytics.daily.map { |day| day[:rate] }.compact).to eq([ 28.57 ].select { false } + analytics.daily.map { |day| day[:rate] }.compact) # a rate exists only for days with 3+ parcels
  end

  it "follows the basis (order date or shipping date) and the company filter, and keeps stores apart" do
    expect(described_class.new(store: store, range: range, basis: "ship", now: now).total).to eq(3) # A, B and F have a shipping date
    expect(described_class.new(store: store, range: range, company: "sendit", now: now).total).to eq(6)
    expect(described_class.new(store: store, range: range, company: "manual", now: now).total).to eq(1)
    expect(described_class.new(store: store, range: range, basis: "nonsense", company: "nonsense", now: now).total).to eq(7)

    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    expect(described_class.new(store: other, range: range, now: now).total).to eq(0)
    empty = described_class.new(store: other, range: range, now: now)
    expect([ empty.delivery_rate, empty.average_days, empty.cost_per_delivered, empty.cost_share ]).to eq([ nil, nil, nil, nil ])
  end
end
