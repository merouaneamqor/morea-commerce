# frozen_string_literal: true

require "rails_helper"
require "support/meta_ads_helpers"

RSpec.describe MetaAds::StructureSync do
  let(:store) { Store.create!(slug: "meta-struct-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-structure-token", token_expires_at: 50.days.from_now) }
  let!(:account) do
    MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1001", name: "Synthetic", currency: "EUR",
      timezone_name: "Europe/Paris", account_status: 1, selected: true)
  end
  let(:now) { Time.utc(2026, 11, 6, 12, 0, 0) }
  let(:requests) { [] }
  let(:campaign_payload) do
    [ { id: "111", name: "Summer CBO", status: "ACTIVE", effective_status: "ACTIVE", objective: "OUTCOME_SALES",
        daily_budget: "5000", lifetime_budget: nil, budget_remaining: "3200", spend_cap: "20000", updated_time: "2026-11-05T10:00:00+0000" } ]
  end
  let(:adset_payload) do
    [ { id: "222", name: "Casa 18-35", campaign_id: "111", status: "ACTIVE", effective_status: "ACTIVE",
        daily_budget: nil, lifetime_budget: nil, budget_remaining: nil, updated_time: "2026-11-05T10:00:00+0000" },
      { id: "223", name: "Rabat ABO", campaign_id: "999", status: "PAUSED", effective_status: "PAUSED",
        daily_budget: "1500", lifetime_budget: nil, budget_remaining: "900", updated_time: "2026-11-05T09:00:00+0000" } ]
  end
  let(:ad_payload) do
    [ { id: "333", name: "Video Alpha", adset_id: "222", campaign_id: "111", status: "ACTIVE", effective_status: "ACTIVE",
        updated_time: "2026-11-05T10:00:00+0000" },
      { id: "334", name: "Orphan", adset_id: "999", campaign_id: "111", status: "PAUSED", effective_status: "PAUSED",
        updated_time: "2026-11-05T10:00:00+0000" } ]
  end
  let(:transport) do
    lambda do |uri, _request|
      requests << uri.path
      data = case uri.path
      when %r{/campaigns$} then campaign_payload
      when %r{/adsets$} then adset_payload
      when %r{/ads$} then ad_payload
      else []
      end
      meta_reply({ data: data })
    end
  end
  let(:client) { MetaAds::Client.new(connection: connection, transport: transport) }

  it "upserts campaigns with status, objective and major-unit budgets, then nested ad sets and ads" do
    usage = described_class.new(ad_account: account, client: client, now: now).call
    expect(usage).to eq(0)
    expect(requests).to eq([
      "/#{MetaAds::Config.api_version}/act_1001/campaigns",
      "/#{MetaAds::Config.api_version}/act_1001/adsets",
      "/#{MetaAds::Config.api_version}/act_1001/ads"
    ])

    campaign = MetaAds::Campaign.find_by!(store: store, meta_id: "111")
    expect(campaign).to have_attributes(
      name: "Summer CBO", status: "ACTIVE", effective_status: "ACTIVE", objective: "OUTCOME_SALES",
      daily_budget: BigDecimal("50"), lifetime_budget: nil, budget_remaining: BigDecimal("32"), spend_cap: BigDecimal("200"),
      last_seen_at: now
    )
    expect(campaign.running?).to be(true)
    expect(campaign.campaign_budget?).to be(true)

    ad_set = MetaAds::AdSet.find_by!(store: store, meta_id: "222")
    expect(ad_set).to have_attributes(campaign_id: campaign.id, name: "Casa 18-35", effective_status: "ACTIVE")
    expect(MetaAds::AdSet.find_by(meta_id: "223")).to be_nil

    ad = MetaAds::Ad.find_by!(store: store, meta_id: "333")
    expect(ad).to have_attributes(campaign_id: campaign.id, ad_set_id: ad_set.id, effective_status: "ACTIVE")
    expect(MetaAds::Ad.find_by(meta_id: "334")).to be_nil
  end

  it "converts zero-decimal currencies without dividing by 100" do
    account.update!(currency: "JPY")
    campaign_payload.first[:daily_budget] = "5000"
    described_class.new(ad_account: account, client: client, now: now).call
    expect(MetaAds::Campaign.find_by!(meta_id: "111").daily_budget).to eq(BigDecimal("5000"))
  end

  it "keeps prior rows when Meta omits a campaign, and updates budgets on re-sync" do
    described_class.new(ad_account: account, client: client, now: now).call
    campaign_payload.first[:daily_budget] = "7500"
    campaign_payload.first[:effective_status] = "PAUSED"
    described_class.new(ad_account: account, client: client, now: now + 1.hour).call
    expect(MetaAds::Campaign.find_by!(meta_id: "111")).to have_attributes(daily_budget: BigDecimal("75"), effective_status: "PAUSED")
  end
end
