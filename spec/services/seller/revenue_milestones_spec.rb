require "rails_helper"

RSpec.describe Seller::RevenueMilestones do
  let(:store) { Store.create!(slug: "ms-#{SecureRandom.hex(5)}", name: "Milestones", currency: "MAD", storefront_enabled: false) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def delivered(mad, store: self.store, status: "delivered", days_ago: 3)
    cust = store.customers.first || store.customers.create!(name: "C", phone: "0600000000")
    store.orders.create!(customer: cust, number: "M#{SecureRandom.hex(4).upcase}", status: status, currency: "MAD", customer_name: "C", customer_phone: cust.phone,
      customer_city: "Fès", customer_address: "x", subtotal_cents: mad * 100, total_cents: mad * 100, delivered_at: days_ago.days.ago, created_at: days_ago.days.ago)
  end

  def milestones = described_class.new(store: store)
  def fills(m) = m.tiers.map(&:fill)

  it "starts at zero with no tier and the first bar empty" do
    m = milestones

    expect(m.revenue_cents).to eq(0)
    expect(m.current).to be_nil
    expect(m.next_tier.key).to eq("pionnier")
    expect(m.remaining_cents).to eq(10_000_000)
    expect(fills(m)).to eq([ 0, 0, 0, 0, 0, 0 ])
  end

  it "fills the first bar in proportion below the first threshold" do
    delivered(50_000)

    m = milestones
    expect(m.current).to be_nil
    expect(fills(m)).to eq([ 50, 0, 0, 0, 0, 0 ])    # 50 000 / 100 000
    expect(m.percent_to_next).to eq(50)
    expect(m.remaining_cents).to eq(5_000_000)         # 50 000,00 MAD to go
  end

  it "unlocks Pionnier at 224 210 MAD and fills the next bar by what lies between the two thresholds" do
    delivered(224_210)

    m = milestones
    expect(m.current.key).to eq("pionnier")
    expect(m.next_tier.key).to eq("doyen")
    expect(m.remaining_cents).to eq(27_579_000)         # 500 000 - 224 210 = 275 790 MAD
    expect(fills(m)).to eq([ 100, 31, 0, 0, 0, 0 ])     # (224 210 - 100 000) / (500 000 - 100 000) = 31,05 %
    expect(m.percent_to_next).to eq(31)
  end

  it "unlocks a tier exactly at its threshold" do
    delivered(500_000)

    m = milestones
    expect(m.current.key).to eq("doyen")
    expect(fills(m)).to eq([ 100, 100, 0, 0, 0, 0 ])
    expect(m.percent_to_next).to eq(0)
  end

  it "never rounds 99,9 % up to a full bar" do
    delivered(499_999)

    expect(fills(milestones)).to eq([ 100, 99, 0, 0, 0, 0 ])
  end

  it "is maxed beyond the last threshold" do
    6.times { delivered(10_000_000) } # 60 000 000 MAD; one order's total is a 4-byte integer, so several orders

    m = milestones
    expect(m.current.key).to eq("titan")
    expect(m.maxed?).to be(true)
    expect(m.next_tier).to be_nil
    expect(m.remaining_cents).to eq(0)
    expect(m.percent_to_next).to eq(100)
    expect(fills(m)).to eq([ 100 ] * 6)
  end

  it "counts only delivered orders (not returned or cancelled) and only this store" do
    delivered(150_000)
    delivered(400_000, status: "returned")
    delivered(400_000, status: "cancelled")
    other = Store.create!(slug: "other-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    delivered(9_000_000, store: other)

    expect(milestones.revenue_cents).to eq(15_000_000)
    expect(milestones.current.key).to eq("pionnier")
  end

  it "reads the same revenue as AccountingStats over the whole life of the store" do
    delivered(12_345, days_ago: 400)
    delivered(54_321, days_ago: 2)
    first = store.orders.minimum(:created_at).in_time_zone(DateRange::ZONE).to_date
    range = DateRange.build(first, DateRange.today)

    expect(milestones.revenue_cents).to eq(AccountingStats.new(store: store, range: range).totals.revenue)
    expect(milestones.revenue_cents).to eq(6_666_600)
  end
end
