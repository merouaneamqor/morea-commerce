# frozen_string_literal: true

require "rails_helper"

RSpec.describe DateRange do
  let(:today) { Date.new(2026, 11, 3) } # a Tuesday
  let(:zone) { Time.find_zone!("Africa/Casablanca") }

  def preset(key, on: today) = described_class.preset(key, today: on)
  def range(from, to, on: today) = described_class.build(Date.parse(from), Date.parse(to), today: on)

  describe "the store's day" do
    it "uses Africa/Casablanca, not the server's (UTC) day" do
      # In January Casablanca is one hour ahead of UTC: 23:30 UTC on 14 January is 00:30 on 15 January there.
      expect(described_class.today(Time.utc(2026, 1, 14, 23, 30))).to eq(Date.new(2026, 1, 15))
      expect(described_class.today(Time.utc(2026, 1, 14, 22, 59))).to eq(Date.new(2026, 1, 14))
    end

    it "follows the zone's own offset whatever it is that day, never a fixed one" do
      [ Time.utc(2026, 1, 14, 23, 30), Time.utc(2026, 2, 25, 23, 30), Time.utc(2026, 6, 14, 23, 30), Time.utc(2026, 11, 3, 23, 30) ].each do |instant|
        expect(described_class.today(instant)).to eq(instant.in_time_zone("Africa/Casablanca").to_date)
      end
    end
  end

  describe "the presets" do
    it "today and yesterday" do
      expect(preset("today")).to have_attributes(from: today, to: today, days: 1)
      expect(preset("yesterday")).to have_attributes(from: Date.new(2026, 11, 2), to: Date.new(2026, 11, 2), days: 1)
    end

    it "the last 3, 7 and 30 days end today and count today" do
      expect(preset("last_3")).to have_attributes(from: Date.new(2026, 11, 1), to: today, days: 3)
      expect(preset("last_7")).to have_attributes(from: Date.new(2026, 10, 28), to: today, days: 7)
      expect(preset("last_30")).to have_attributes(from: Date.new(2026, 10, 5), to: today, days: 30)
    end

    it "this month is the month to date, last month is the whole previous month" do
      expect(preset("this_month")).to have_attributes(from: Date.new(2026, 11, 1), to: today)
      expect(preset("last_month")).to have_attributes(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31), days: 31)
    end

    it "last month across a year boundary" do
      expect(preset("last_month", on: Date.new(2026, 1, 15))).to have_attributes(from: Date.new(2025, 12, 1), to: Date.new(2025, 12, 31))
    end

    it "this year is the year to date" do
      expect(preset("this_year")).to have_attributes(from: Date.new(2026, 1, 1), to: today, days: 307)
    end

    it "quarters: whole past quarters, the current one to date" do
      expect(preset("q1")).to have_attributes(from: Date.new(2026, 1, 1), to: Date.new(2026, 3, 31), days: 90)
      expect(preset("q2")).to have_attributes(from: Date.new(2026, 4, 1), to: Date.new(2026, 6, 30), days: 91)
      expect(preset("q3")).to have_attributes(from: Date.new(2026, 7, 1), to: Date.new(2026, 9, 30), days: 92)
      expect(preset("q4")).to have_attributes(from: Date.new(2026, 10, 1), to: today, days: 34)
    end

    it "a quarter that has not started does not exist" do
      early = Date.new(2026, 1, 15)
      expect(preset("q1", on: early)).to have_attributes(from: Date.new(2026, 1, 1), to: early)
      %w[q2 q3 q4].each { |key| expect(preset(key, on: early)).to be_nil }
    end

    it "an unknown preset is nil" do
      expect(preset("forever")).to be_nil
    end

    it "is never in the future" do
      described_class::PRESETS.filter_map { |key| preset(key) }.each { |found| expect(found.to).to be <= today }
    end
  end

  describe "a custom range" do
    it "can start and end on the same day (a single whole day)" do
      single = range("2026-11-03", "2026-11-03")
      expect(single).to have_attributes(from: today, to: today, days: 1)
      expect(single.time_range).to eq(zone.local(2026, 11, 3, 0, 0, 0)...zone.local(2026, 11, 4, 0, 0, 0))
    end

    it "can span two months" do
      across = range("2026-10-20", "2026-11-03")
      expect(across.days).to eq(15)
      expect(across.dates.map(&:month).uniq).to eq([ 10, 11 ])
    end

    it "swaps a start that is after the end" do
      expect(range("2026-10-25", "2026-10-10")).to have_attributes(from: Date.new(2026, 10, 10), to: Date.new(2026, 10, 25))
    end

    it "cuts an end in the future to today, and refuses a range that starts in the future" do
      expect(range("2026-11-01", "2026-11-30")).to have_attributes(from: Date.new(2026, 11, 1), to: today)
      expect(range("2026-11-04", "2026-11-10")).to be_nil
      expect(range("2026-11-10", "2026-11-04")).to be_nil
    end

    it "refuses a range longer than five years instead of cutting it silently" do
      expect(range("2020-01-01", "2026-11-03")).to be_nil
      expect(range("2021-11-04", "2026-11-03")).to be_present
    end
  end

  describe "the end is inclusive, in the store's timezone" do
    let(:last_day) { range("2026-10-01", "2026-10-31") }

    it "counts an order at 23:59 on the last day, and not one at 00:00 the next day" do
      inside = zone.local(2026, 10, 31, 23, 59, 0)
      last_microsecond = zone.local(2026, 10, 31, 23, 59, 59) + 0.999999
      next_day = zone.local(2026, 11, 1, 0, 0, 0)
      first_second = zone.local(2026, 10, 1, 0, 0, 0)
      before = zone.local(2026, 9, 30, 23, 59, 59)
      expect([ inside, last_microsecond, first_second ].map { |time| last_day.time_range.cover?(time) }).to all(be(true))
      expect([ next_day, before ].map { |time| last_day.time_range.cover?(time) }).to all(be(false))
    end

    it "uses the store's midnight, not UTC's: in January 23:59 in Casablanca is 22:59 UTC and still counts for that day" do
      january = range("2026-01-01", "2026-01-31", on: Date.new(2026, 2, 10))
      expect(january.time_range.cover?(Time.utc(2026, 1, 31, 22, 59, 0))).to be(true)
      expect(january.time_range.cover?(Time.utc(2026, 1, 31, 23, 0, 0))).to be(false) # already 00:00 on 1 February there
      expect(january.time_range.cover?(Time.utc(2025, 12, 31, 23, 0, 0))).to be(true) # 00:00 on 1 January there
      expect(january.time_range.cover?(Time.utc(2025, 12, 31, 22, 59, 59))).to be(false)
    end

    it "queries orders with it: the order at 23:59 on the last day is in, the one at midnight is out" do
      store = Store.create!(name: "Plage #{SecureRandom.hex(3)}", slug: "plage-#{SecureRandom.hex(4)}", currency: "MAD")
      customer = store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{SecureRandom.hex(3)}@example.test")
      make = lambda do |at|
        store.orders.create!(customer: customer, number: "R#{SecureRandom.hex(4)}", status: "new", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
          customer_city: "Fès", customer_address: "Rue 1", total_cents: 100, created_at: at)
      end
      kept = [ make.(zone.local(2026, 10, 31, 23, 59, 0)), make.(zone.local(2026, 10, 1, 0, 0, 0)) ]
      make.(zone.local(2026, 11, 1, 0, 0, 0))
      make.(zone.local(2026, 9, 30, 23, 59, 59))
      expect(store.orders.where(created_at: last_day.time_range).pluck(:id)).to match_array(kept.map(&:id))
    end
  end

  describe "the previous period" do
    it "is the same number of days just before" do
      expect(range("2026-10-25", "2026-11-03").previous).to have_attributes(from: Date.new(2026, 10, 15), to: Date.new(2026, 10, 24), days: 10)
      expect(range("2026-11-03", "2026-11-03").previous).to have_attributes(from: Date.new(2026, 11, 2), to: Date.new(2026, 11, 2))
      expect(preset("last_month").previous).to have_attributes(from: Date.new(2026, 8, 31), to: Date.new(2026, 9, 30), days: 31)
    end

    it "sits right against the range, with no gap and no overlap" do
      [ preset("last_7"), preset("this_month"), range("2026-10-20", "2026-11-03") ].each do |current|
        expect(current.previous.to + 1).to eq(current.from)
        expect(current.previous.days).to eq(current.days)
      end
    end
  end

  describe "naming a range" do
    it "finds the preset a range is, and nil for a custom one" do
      expect(preset("last_7").preset_key).to eq("last_7")
      expect(preset("last_month").preset_key).to eq("last_month")
      expect(range("2026-10-20", "2026-11-03").preset_key).to be_nil
    end

    it "keeps the first preset when two are the same days, unless the URL says which one was picked" do
      both = preset("this_month") # 1 to 3 November is also "last 3 days"
      expect(both.preset_key).to eq("last_3")
      expect(described_class.hinted_preset("this_month", both)).to eq("this_month")
      expect(described_class.hinted_preset("last_7", both)).to be_nil # a hint that is not that range is ignored
      expect(described_class.hinted_preset("nonsense", both)).to be_nil
    end
  end

  describe "reading dates" do
    it "reads ISO dates only" do
      expect(described_class.parse_date("2026-10-01")).to eq(Date.new(2026, 10, 1))
      [ nil, "", "2026-13-01", "2026-02-30", "01/10/2026", "2026-1-1", "2026-10-01T00:00", 20261001, [ "2026-10-01" ], "'; DROP TABLE" ].each do |bad|
        expect(described_class.parse_date(bad)).to be_nil, bad.inspect
      end
    end

    it "builds from URL params, needing both dates" do
      expect(described_class.from_params({ from: "2026-10-01", to: "2026-10-31" }, today: today)).to have_attributes(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))
      expect(described_class.from_params({ from: "2026-10-01" }, today: today)).to be_nil
      expect(described_class.from_params({ from: "bad", to: "2026-10-31" }, today: today)).to be_nil
    end
  end

  describe "remembering the last choice" do
    it "remembers a preset by name, so it stays relative, and a custom range by its dates" do
      week = preset("last_7")
      expect(week.to_cookie).to eq("p:last_7")
      expect(described_class.from_cookie("p:last_7", today: Date.new(2026, 12, 1))).to have_attributes(from: Date.new(2026, 11, 25), to: Date.new(2026, 12, 1))
      custom = range("2026-10-20", "2026-11-03")
      expect(custom.to_cookie).to eq("c:2026-10-20:2026-11-03")
      expect(described_class.from_cookie("c:2026-10-20:2026-11-03", today: today)).to eq(custom)
    end

    it "remembers the preset the seller picked when two presets are the same days" do
      expect(preset("this_month").to_cookie("this_month")).to eq("p:this_month")
    end

    it "ignores a damaged or hostile cookie" do
      [ nil, "", "p:", "p:forever", "p:q9", "c:2026-10-20", "c:bad:bad", "x:last_7", "p:last_7;evil", "c:2026-11-10:2026-11-20" ].each do |bad|
        expect(described_class.from_cookie(bad, today: today)).to be_nil, bad.inspect
      end
    end
  end
end
