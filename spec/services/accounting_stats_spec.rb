# frozen_string_literal: true

require "rails_helper"

# Every expected number below was worked out by hand (see the comments); none is read back from the code.
RSpec.describe AccountingStats do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { Store.create!(name: "Compta #{suffix}", slug: "compta-#{suffix}", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "client-#{suffix}@example.test") }
  let(:zone) { Time.find_zone!("Africa/Casablanca") }
  let(:now) { zone.local(2026, 11, 5, 12, 0) }
  let(:october) { described_class.new(store: store, month: "2026-10", now: now) }

  # items: [[quantity, unit cost in centimes or nil], ...]
  def order(status:, total:, items: [ [ 1, 0 ] ], delivered_at: nil, shipped_at: nil, returned_at: nil, delivery_fee: nil, return_fee: nil, currency: "MAD", archived_at: nil)
    record = store.orders.create!(customer: customer, number: "T#{SecureRandom.hex(4)}", status: status, currency: currency,
      customer_name: "Client", customer_phone: "0612345678", customer_city: "Fès", customer_address: "Rue 1",
      subtotal_cents: total, total_cents: total, delivered_at: delivered_at, shipped_at: shipped_at, returned_at: returned_at,
      delivery_fee_cents: delivery_fee, return_fee_cents: return_fee, archived_at: archived_at, created_at: zone.local(2026, 8, 1))
    items.each { |quantity, cost| record.order_items.create!(product_name: "Montre", quantity: quantity, unit_price_cents: total / items.size, total_cents: total / items.size, unit_cost_cents: cost) }
    record
  end

  def spend(on:, amount:, currency: "MAD", level: "campaign", converted: true, account: nil, campaign_id: "111")
    connection = MetaAds::Connection.find_by(store_id: store.id) || MetaAds::Connection.create!(store: store, access_token: "synthetic-token")
    account ||= (MetaAds::AdAccount.find_by(store_id: store.id) || MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1", name: "A", currency: "EUR",
      timezone_name: "UTC", account_status: 1))
    campaign = account.campaigns.find_by(meta_id: campaign_id) || MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: campaign_id, name: "C#{campaign_id}")
    ad_set = account.ad_sets.first || MetaAds::AdSet.create!(store: store, ad_account: account, campaign: campaign, meta_id: "222", name: "S")
    ad = account.ads.first || MetaAds::Ad.create!(store: store, ad_account: account, ad_set: ad_set, campaign: campaign, meta_id: "333", name: "Ad")
    MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, level: level, ad_set: (ad_set if level == "ad"), ad: (ad if level == "ad"), date: on,
      currency: "EUR", spend: 1, synced_at: Time.current, spend_display: (amount if converted), display_currency: (currency if converted), fx_rate: (BigDecimal("1.1") if converted),
      fx_date: on, meta_campaign_id: campaign_id)
  end

  # October 2026 (previous period of the same length: 31 days, 31 August to 30 September).
  #   delivered in October: D1 20 000 (2 x 3 000 cost, fee 2 500), D2 15 050 (4 025, fee 2 450),
  #   D3 10 000 (2 000, fee 2 500) at 23:59 on 31 October, D5 5 000 (1 000, fee 2 500) at 00:00:00 on 1 October
  #   returned in October: R1 (fee 1 500; its 30 000 and 8 000 cost must not count)
  #   never counted: D4 delivered 00:00:30 on 1 November, R2 returned in November, cancelled (even with a delivered_at),
  #   new, confirmed, unreachable, postponed, in transit
  #   ads: 60.2275 + 60.2275 on 10 Oct = 12 045.5 -> 12 046 (half up), 30.00 on 20 Oct = 3 000
  #   previous: P1 25 000 (5 000, fee 2 500) on 15 Sep, P2 10 000 (2 000, fee 2 500) on 31 Aug at noon,
  #   P3 77 777 on 30 Aug (outside the 31 days)
  def build_october
    @product = store.products.create!(name: "Montre", slug: "montre-#{suffix}", price_cents: 10_000, cost_cents: 3_000, status: "active")
    @d1 = order(status: "delivered", total: 20_000, items: [ [ 2, 3_000 ] ], delivered_at: zone.local(2026, 10, 10, 12, 0), delivery_fee: 2_500)
    @d2 = order(status: "delivered", total: 15_050, items: [ [ 1, 4_025 ] ], delivered_at: zone.local(2026, 10, 10, 18, 30), delivery_fee: 2_450)
    order(status: "delivered", total: 10_000, items: [ [ 1, 2_000 ] ], delivered_at: zone.local(2026, 10, 31, 23, 59), delivery_fee: 2_500)
    order(status: "delivered", total: 5_000, items: [ [ 1, 1_000 ] ], delivered_at: zone.local(2026, 10, 1, 0, 0, 0), delivery_fee: 2_500)
    order(status: "delivered", total: 99_999, items: [ [ 1, 50_000 ] ], delivered_at: zone.local(2026, 11, 1, 0, 0, 30), delivery_fee: 2_500)
    order(status: "returned", total: 30_000, items: [ [ 1, 8_000 ] ], returned_at: zone.local(2026, 10, 12, 9, 0), return_fee: 1_500, delivery_fee: 2_500)
    order(status: "returned", total: 30_000, items: [ [ 1, 8_000 ] ], returned_at: zone.local(2026, 11, 2, 9, 0), return_fee: 1_500)
    order(status: "cancelled", total: 50_000, items: [ [ 1, 1_000 ] ], delivered_at: zone.local(2026, 10, 10, 9, 0))
    %w[new confirmed unreachable postponed in_transit].each { |status| order(status: status, total: 40_000, items: [ [ 1, 1_000 ] ], shipped_at: zone.local(2026, 10, 10, 9, 0)) }
    order(status: "delivered", total: 25_000, items: [ [ 1, 5_000 ] ], delivered_at: zone.local(2026, 9, 15, 12, 0), delivery_fee: 2_500)
    order(status: "delivered", total: 10_000, items: [ [ 1, 2_000 ] ], delivered_at: zone.local(2026, 8, 31, 12, 0), delivery_fee: 2_500)
    order(status: "delivered", total: 77_777, items: [ [ 1, 1_000 ] ], delivered_at: zone.local(2026, 8, 30, 12, 0), delivery_fee: 2_500)
    spend(on: Date.new(2026, 10, 10), amount: BigDecimal("60.2275"), campaign_id: "111")
    spend(on: Date.new(2026, 10, 10), amount: BigDecimal("60.2275"), campaign_id: "112")
    spend(on: Date.new(2026, 10, 20), amount: BigDecimal("30"))
    spend(on: Date.new(2026, 10, 25), amount: BigDecimal("999"), currency: "USD") # another currency: never mixed in
    spend(on: Date.new(2026, 10, 26), amount: nil, converted: false) # not converted yet
    spend(on: Date.new(2026, 10, 10), amount: BigDecimal("888"), level: "ad") # same money seen at ad level: not added again
  end

  describe "October, delivered mode" do
    before { build_october }

    it "counts the right orders and gets every figure by hand" do
      t = october.totals
      expect(t.orders).to eq(4)
      expect(t.revenue).to eq(50_050)          # 20 000 + 15 050 + 10 000 + 5 000
      expect(t.goods).to eq(13_025)            # 2 x 3 000 + 4 025 + 2 000 + 1 000
      expect(t.delivery).to eq(11_450)         # 2 500 + 2 450 + 2 500 + 2 500 delivered, + 1 500 return fee
      expect(t.ads).to eq(15_046)              # 12 046 + 3 000
      expect(t.gross_margin).to eq(37_025)     # 50 050 - 13 025
      expect(t.expenses).to eq(39_521)         # 13 025 + 11 450 + 15 046
      expect(t.net).to eq(10_529)              # 50 050 - 39 521
      expect(t.average_basket).to eq(Rational(25_025, 2)) # 50 050 / 4 = 12 512.5
      expect(t.margin).to eq(Rational(10_529, 50_050))
    end

    it "uses the store's day: 23:59 on the 31st is October, 00:00:30 on the 1st is November, midnight on the 1st is October" do
      expect(october.lines.select { |line| line.kind == "delivered" }.map(&:revenue)).to match_array([ 20_000, 15_050, 10_000, 5_000 ])
      expect(described_class.new(store: store, month: "2026-11", now: now).totals.revenue).to eq(99_999)
      expect(october.daily.keys.first).to eq(Date.new(2026, 10, 1))
      expect(october.daily.keys.last).to eq(Date.new(2026, 10, 31))
      expect(october.daily[Date.new(2026, 10, 1)].revenue).to eq(5_000)
      expect(october.daily[Date.new(2026, 10, 31)].revenue).to eq(10_000)
      expect(october.daily[Date.new(2026, 10, 10)].revenue).to eq(35_050)
      expect(october.daily[Date.new(2026, 10, 10)].goods).to eq(10_025)
    end

    it "gives a returned order no revenue and no cost of goods, only its return fee" do
      returned = october.lines.select { |line| line.kind == "returned" }
      expect(returned.length).to eq(1)
      expect(returned.first).to have_attributes(revenue: 0, goods: 0, delivery: 1_500, ads: 0)
    end

    it "never counts cancelled, new, confirmed, unreachable, postponed or in-transit orders" do
      expect(october.lines.map(&:order_id).compact.length).to eq(5) # 4 delivered + 1 returned
    end

    it "counts delivered orders that were archived" do
      order(status: "delivered", total: 1_000, delivered_at: zone.local(2026, 10, 15, 10, 0), delivery_fee: 0, archived_at: now)
      expect(october.totals.revenue).to eq(51_050)
    end

    it "keeps old months still when a product cost, a fee or the carrier's live fee changes later" do
      before = october.totals.to_h
      @product.update!(cost_cents: 9_999)
      @d1.update!(sendit_fee: 99)
      @d2.order_items.update_all(product_id: @product.id)
      expect(described_class.new(store: store, month: "2026-10", now: now).totals.to_h).to eq(before)
    end

    it "adds a day's ad spend as decimals and turns it into centimes once, half up; other currencies, unconverted rows and ad rows stay out" do
      expect(october.lines.select { |line| line.kind == "ads" }.to_h { |line| [ line.date, line.ads ] }).to eq(Date.new(2026, 10, 10) => 12_046, Date.new(2026, 10, 20) => 3_000)
      expect(october.warnings[:unconverted_ad_rows]).to eq(2) # the USD row and the row without a conversion
    end

    it "compares with the previous period of the same length (31 August to 30 September)" do
      expect(october.previous_range).to eq(Date.new(2026, 8, 31)..Date.new(2026, 9, 30))
      p = october.previous_totals
      expect([ p.orders, p.revenue, p.goods, p.delivery, p.ads ]).to eq([ 2, 35_000, 7_000, 5_000, 0 ])
      expect(october.change(:revenue)).to eq(43)                             # (50 050 - 35 000) / 35 000
      expect(october.change(:delivery)).to eq(129)                           # (11 450 - 5 000) / 5 000
      expect(october.change(:goods)).to eq(Rational(6_025 * 100, 7_000))
      expect(october.change(:orders)).to eq(100)                             # (4 - 2) / 2
      expect(october.change(:ads)).to eq(:new)                               # previous is 0
      expect(october.margin_change_points).to eq((Rational(10_529, 50_050) - Rational(23_000, 35_000)) * 100) # previous net = 35 000 - 7 000 - 5 000 = 23 000
    end

    it "splits 100 into exactly 100.0 with the biggest remainders getting the last tenths" do
      # goods 260.24, delivery 228.77, ads 300.62, profit 210.37 tenths -> floors 260 228 300 210 (998), +1 to delivery and ads
      expect(october.split_per_100).to eq(shares: { goods: 260, delivery: 229, ads: 301, profit: 210 }, loss: false)
    end

    it "reports what is missing instead of hiding it" do
      expect(october.warnings).to include(missing_cost_orders: 0, missing_delivery_fee_orders: 0, missing_return_fee_orders: 0)
      order(status: "delivered", total: 1_000, items: [ [ 1, nil ] ], delivered_at: zone.local(2026, 10, 15, 10, 0), delivery_fee: nil)
      order(status: "returned", total: 1_000, returned_at: zone.local(2026, 10, 16, 10, 0), return_fee: nil)
      fresh = described_class.new(store: store, month: "2026-10", now: now)
      expect(fresh.warnings).to include(missing_cost_orders: 1, missing_delivery_fee_orders: 1, missing_return_fee_orders: 1)
      expect(fresh.totals.revenue).to eq(51_050) # counted, with 0 cost and 0 fee, and flagged
    end

    it "satisfies every always-true check" do
      expect(october.invariants).to eq([])
      t = october.totals
      expect(t.gross_margin).to eq(t.revenue - t.goods)
      expect(t.expenses + t.net).to eq(t.revenue)
      expect(october.split_per_100[:shares].values.sum).to eq(1_000)
      expect(october.lines.sum(&:revenue)).to eq(t.revenue)
      expect(october.daily.values.sum(&:net)).to eq(t.net)
    end
  end

  describe "shipped mode" do
    it "filters by shipped_at: delivered orders carry revenue, returned ones their return fee, anything still on the road nothing" do
      order(status: "delivered", total: 20_000, items: [ [ 1, 6_000 ] ], shipped_at: zone.local(2026, 10, 5, 10, 0), delivered_at: zone.local(2026, 11, 2, 10, 0), delivery_fee: 2_500)
      order(status: "delivered", total: 8_000, items: [ [ 1, 1_000 ] ], shipped_at: zone.local(2026, 9, 30, 23, 30), delivered_at: zone.local(2026, 10, 2, 10, 0), delivery_fee: 2_500)
      order(status: "returned", total: 9_000, items: [ [ 1, 3_000 ] ], shipped_at: zone.local(2026, 10, 6, 10, 0), returned_at: zone.local(2026, 11, 3, 10, 0), return_fee: 1_800)
      order(status: "in_transit", total: 7_000, items: [ [ 1, 2_000 ] ], shipped_at: zone.local(2026, 10, 7, 10, 0))
      shipped = described_class.new(store: store, month: "2026-10", basis: "shipped", now: now)
      delivered = described_class.new(store: store, month: "2026-10", basis: "delivered", now: now)

      expect(shipped.totals.to_h).to eq(orders: 1, revenue: 20_000, goods: 6_000, delivery: 4_300, ads: 0) # 2 500 + 1 800 return fee
      expect(delivered.totals.to_h).to eq(orders: 1, revenue: 8_000, goods: 1_000, delivery: 2_500, ads: 0)
      expect(shipped.invariants).to eq([])
      expect(shipped.daily[Date.new(2026, 10, 5)].revenue).to eq(20_000)
    end

    it "ignores an unknown basis and falls back to delivered" do
      expect(described_class.new(store: store, basis: "whatever", now: now).basis).to eq("delivered")
    end
  end

  describe "a month with no orders" do
    it "shows dashes (nil), not zeros or errors, and every check still holds" do
      t = october.totals
      expect(t.to_h).to eq(orders: 0, revenue: 0, goods: 0, delivery: 0, ads: 0)
      expect(t.average_basket).to be_nil
      expect(t.margin).to be_nil
      expect(october.split_per_100).to be_nil
      expect(october.change(:revenue)).to be_nil
      expect(october.change(:average_basket)).to be_nil
      expect(october.margin_change_points).to be_nil
      expect(october.daily.length).to eq(31)
      expect(october.invariants).to eq([])
    end

    it "says :new only when something exists now and nothing existed before" do
      order(status: "delivered", total: 10_000, delivered_at: zone.local(2026, 10, 10, 10, 0), delivery_fee: 0)
      expect(october.change(:revenue)).to eq(:new)
    end
  end

  describe "revenue 0 but a return fee" do
    it "has a loss, no margin and no split, and the checks hold" do
      order(status: "returned", total: 10_000, returned_at: zone.local(2026, 10, 10, 10, 0), return_fee: 1_500)
      expect(october.totals.net).to eq(-1_500)
      expect(october.totals.margin).to be_nil
      expect(october.split_per_100).to be_nil
      expect(october.invariants).to eq([])
    end
  end

  describe "a month that loses money" do
    it "gives profit 0 and shares the 100 between the three expenses, adding up to exactly 100.0" do
      order(status: "delivered", total: 10_000, items: [ [ 1, 8_000 ] ], delivered_at: zone.local(2026, 10, 10, 10, 0), delivery_fee: 5_000)
      expect(october.totals.net).to eq(-3_000)
      # expenses 13 000: goods 615.38, delivery 384.61 tenths -> floors 615 and 384 (999), +1 to delivery
      expect(october.split_per_100).to eq(shares: { goods: 615, delivery: 385, ads: 0, profit: 0 }, loss: true)
      expect(october.invariants).to eq([])
    end
  end

  describe "months and the current month" do
    it "uses the month to date for the current month and compares with the same number of days before" do
      order(status: "delivered", total: 10_000, delivered_at: zone.local(2026, 11, 3, 10, 0), delivery_fee: 0)
      order(status: "delivered", total: 4_000, delivered_at: zone.local(2026, 10, 30, 10, 0), delivery_fee: 0)
      november = described_class.new(store: store, month: "2026-11", now: now)
      expect(november.range).to eq(Date.new(2026, 11, 1)..Date.new(2026, 11, 5))
      expect(november.previous_range).to eq(Date.new(2026, 10, 27)..Date.new(2026, 10, 31))
      expect(november.change(:revenue)).to eq(150) # (10 000 - 4 000) / 4 000
    end

    it "falls back to the current month for a missing, malformed or future month" do
      [ nil, "", "garbage", "2026-13", "2027-01", "2026-1" ].each do |value|
        expect(described_class.new(store: store, month: value, now: now).month).to eq(Date.new(2026, 11, 1)), "month #{value.inspect}"
      end
    end

    it "does not mix another currency's orders in" do
      order(status: "delivered", total: 10_000, delivered_at: zone.local(2026, 10, 10, 10, 0), delivery_fee: 0, currency: "EUR")
      expect(october.totals.revenue).to eq(0)
    end

    it "treats DH and MAD as the same currency" do
      order(status: "delivered", total: 10_000, delivered_at: zone.local(2026, 10, 10, 10, 0), delivery_fee: 0, currency: "DH")
      expect(october.totals.revenue).to eq(10_000)
    end
  end

  describe "receivables and inventory" do
    it "counts delivered parcels whose cash was not recorded, and stock at purchase price" do
      order(status: "delivered", total: 12_000, delivered_at: zone.local(2026, 10, 10, 10, 0), delivery_fee: 0)
      paid = order(status: "delivered", total: 9_000, delivered_at: zone.local(2026, 10, 11, 10, 0), delivery_fee: 0)
      paid.update_columns(collected_cents: 9_000, collected_at: now)
      store.products.create!(name: "A", slug: "a-#{suffix}", price_cents: 5_000, cost_cents: 1_000, stock: 10, status: "active")
      store.products.create!(name: "B", slug: "b-#{suffix}", price_cents: 5_000, cost_cents: 2_500, stock: 0, status: "active")
      store.products.create!(name: "C", slug: "c-#{suffix}", price_cents: 5_000, cost_cents: nil, stock: 4, status: "active")
      expect(october.receivables).to eq(cents: 12_000, parcels: 1)
      expect(october.inventory).to eq(cents: 10_000, products: 3, out_of_stock: 1, missing_cost: 1)
    end
  end

  describe "properties over many random orders" do
    it "keeps every always-true check, whatever the mix, and the export lines add up to the totals" do
      random = Random.new(2026)
      40.times do
        status = %w[delivered delivered delivered returned cancelled new in_transit unreachable postponed].sample(random: random)
        day = zone.local(2026, 10, random.rand(1..31), random.rand(0..23), random.rand(0..59))
        order(status: status, total: random.rand(1..99_999), items: Array.new(random.rand(1..3)) { [ random.rand(1..4), random.rand(0..9_999) ] },
          delivered_at: (day if %w[delivered cancelled].include?(status)), returned_at: (day if status == "returned"), shipped_at: day,
          delivery_fee: random.rand(0..4_000), return_fee: random.rand(0..4_000))
      end
      12.times { |index| spend(on: Date.new(2026, 10, index + 1), amount: BigDecimal(random.rand(1..50_000)) / 7) }
      %w[delivered shipped].each do |basis|
        stats = described_class.new(store: store, month: "2026-10", basis: basis, now: now)
        expect(stats.invariants).to eq([]), "#{basis}: #{stats.invariants}"
        expect(AccountingExport.new(stats).totals).to eq([ stats.totals.revenue, stats.totals.goods, stats.totals.delivery, stats.totals.ads ])
      end
    end
  end
end
