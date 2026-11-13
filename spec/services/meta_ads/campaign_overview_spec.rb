# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::CampaignOverview do
  let(:store) { Store.create!(slug: "meta-ov-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-overview-token") }
  let!(:account) do
    MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1001", name: "Casa Ads",
      currency: "EUR", timezone_name: "Europe/Paris", account_status: 1, selected: true)
  end
  let(:range) { travel_to(Time.utc(2026, 11, 6, 12)) { DateRange.build(Date.new(2026, 11, 1), Date.new(2026, 11, 6)) } }
  let!(:product) { store.products.create!(name: "Robe Lin", slug: "robe-lin", price_cents: 29_000, status: "active") }
  let!(:campaign) do
    MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: "111", name: "Summer Robe Lin", status: "ACTIVE",
      effective_status: "ACTIVE", objective: "OUTCOME_SALES", daily_budget: 50, budget_remaining: 20, last_seen_at: Time.current)
  end
  let!(:paused) do
    MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: "112", name: "Winter", status: "PAUSED",
      effective_status: "PAUSED", last_seen_at: Time.current)
  end
  let!(:ad_set) { MetaAds::AdSet.create!(store: store, ad_account: account, campaign: paused, meta_id: "222", name: "Set", daily_budget: 15) }
  let!(:ad) { MetaAds::Ad.create!(store: store, ad_account: account, campaign: campaign, ad_set: MetaAds::AdSet.create!(store: store, ad_account: account, campaign: campaign, meta_id: "221", name: "Main"), meta_id: "333", name: "Video", effective_status: "ACTIVE") }

  before do
    MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, level: "campaign", date: Date.new(2026, 11, 3),
      currency: "EUR", spend: 10, spend_display: 108, display_currency: "MAD", fx_rate: 10.8, fx_date: Date.new(2026, 11, 3),
      impressions: 1000, clicks: 40, conversions: 2, conversion_value: 90, synced_at: Time.current, meta_campaign_id: "111")
    MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: paused, level: "campaign", date: Date.new(2026, 11, 3),
      currency: "EUR", spend: 4, spend_display: 43.2, display_currency: "MAD", fx_rate: 10.8, fx_date: Date.new(2026, 11, 3),
      impressions: 200, clicks: 10, conversions: 0, conversion_value: 0, synced_at: Time.current, meta_campaign_id: "112")
    MetaAds::ProductLink.create!(store: store, product: product, object_type: "campaign", meta_id: "111", source: "auto")
  end

  it "lists selected-account campaigns with spend, ROAS, budgets, running ads and product links" do
    overview = described_class.new(store: store, range: range)
    rows = overview.rows
    expect(rows.map { |row| row.campaign.meta_id }).to eq(%w[111 112])

    top = rows.first
    expect(top).to have_attributes(
      spend: BigDecimal("10"), spend_display: BigDecimal("108"), conversions: BigDecimal("2"),
      daily_budget: BigDecimal("50"), budget_level: "campaign", active_ads: 1, total_ads: 1,
      link_source: "auto", effective_status: "ACTIVE"
    )
    expect(top.product).to eq(product)
    expect(top.roas).to eq((BigDecimal("90") / BigDecimal("10")).round(4))

    paused_row = rows.last
    expect(paused_row).to have_attributes(daily_budget: BigDecimal("15"), budget_level: "ad_sets", effective_status: "PAUSED")

    expect(overview.totals).to include(spend: BigDecimal("151.2"), active_campaigns: 1, campaigns: 2, currency: "MAD")
  end

  it "never includes another store's campaigns" do
    other = Store.create!(slug: "meta-ov-other-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    other_connection = MetaAds::Connection.create!(store: other, access_token: "other")
    other_account = MetaAds::AdAccount.create!(store: other, connection: other_connection, meta_ad_account_id: "act_9999",
      name: "Foreign", currency: "EUR", timezone_name: "UTC", account_status: 1, selected: true)
    MetaAds::Campaign.create!(store: other, ad_account: other_account, meta_id: "999", name: "Foreign", effective_status: "ACTIVE", last_seen_at: Time.current)

    expect(described_class.new(store: store, range: range).rows.map { |row| row.campaign.meta_id }).to eq(%w[111 112])
  end
end
