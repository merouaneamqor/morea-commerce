# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::Fx do
  let(:fetches) { [] }
  let(:answer) { { "result" => "success", "rates" => { "MAD" => 10.8, "USD" => 1.0 }, "time_last_update_unix" => Time.utc(2026, 11, 3, 0, 2).to_i } }
  let(:fx) { described_class.new(fetcher: ->(base) { fetches << base; answer }) }

  it "needs no rate between a currency and itself, and reads DH as MAD" do
    expect(fx.quote("MAD", "DH", on: Date.new(2026, 11, 3))).to have_attributes(rate: 1, date: Date.new(2026, 11, 3))
    expect(fetches).to be_empty
  end

  it "fetches the rate once, stores it with its date and source, and reuses it" do
    first = fx.quote("USD", "MAD", on: Date.new(2026, 11, 3))
    expect(first).to have_attributes(rate: BigDecimal("10.8"), date: Date.new(2026, 11, 3))
    described_class.new(fetcher: ->(_base) { raise "must not fetch again" }).quote("usd", "mad", on: Date.new(2026, 11, 3))
    expect(fetches).to eq([ "USD" ])
    expect(ExchangeRate.where(base_currency: "USD", quote_currency: "MAD").pluck(:source, :rate_date)).to eq([ [ "open.er-api.com", Date.new(2026, 11, 3) ] ])
  end

  it "uses the closest rate on record for older days and reports that rate's own date" do
    fx.quote("USD", "MAD", on: Date.new(2026, 11, 3))
    expect(fx.quote("USD", "MAD", on: Date.new(2026, 10, 10))).to have_attributes(rate: BigDecimal("10.8"), date: Date.new(2026, 11, 3))
    expect(fx.quote("USD", "MAD", on: Date.new(2026, 11, 20))).to have_attributes(date: Date.new(2026, 11, 3))
  end

  it "prefers the latest earlier rate over a later one" do
    ExchangeRate.create!(base_currency: "USD", quote_currency: "MAD", rate: 9.9, rate_date: Date.new(2026, 10, 1), source: "test", fetched_at: Time.current)
    ExchangeRate.create!(base_currency: "USD", quote_currency: "MAD", rate: 10.8, rate_date: Date.new(2026, 11, 3), source: "test", fetched_at: Time.current)
    expect(fx.quote("USD", "MAD", on: Date.new(2026, 10, 15))).to have_attributes(rate: BigDecimal("9.9"), date: Date.new(2026, 10, 1))
  end

  it "returns nothing instead of inventing a rate when the source fails or answers badly" do
    [ nil, { "result" => "error" }, { "result" => "success", "rates" => { "MAD" => "abc" }, "time_last_update_unix" => 1 },
      { "result" => "success", "rates" => { "MAD" => -2 }, "time_last_update_unix" => 1 }, { "result" => "success", "rates" => {}, "time_last_update_unix" => 1 } ].each do |bad|
      expect(described_class.new(fetcher: ->(_base) { bad }).quote("USD", "MAD", on: Date.new(2026, 11, 3))).to be_nil
    end
    expect(ExchangeRate.count).to eq(0)
  end
end
