# frozen_string_literal: true

require "rails_helper"
require "support/meta_ads_helpers"

RSpec.describe MetaAds::InsightsSync do
  let(:store) { Store.create!(slug: "meta-sync-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-sync-token", token_expires_at: 50.days.from_now) }
  let(:currency) { "EUR" }
  let(:timezone) { "Europe/Paris" }
  let!(:account) do
    MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1001", name: "Synthetic", currency: currency, timezone_name: timezone,
      account_status: 1, selected: true, next_sync_at: Time.current)
  end
  let(:now) { Time.utc(2026, 11, 4, 10, 0, 0) }
  let(:rate_fetches) { [] }
  let(:fx) do
    fetcher = lambda do |base|
      rate_fetches << base
      { "result" => "success", "base_code" => base, "rates" => { "MAD" => 10.8 }, "time_last_update_unix" => Time.utc(2026, 11, 3, 0, 2).to_i }
    end
    MetaAds::Fx.new(fetcher: fetcher)
  end
  let(:requests) { [] }
  let(:headers) { {} }
  let(:purchase) { { action_type: "purchase", value: "3" } }
  let(:campaign_rows) do
    [ { campaign_id: "111", campaign_name: "Summer", spend: "10.50", impressions: "1000", reach: "800", clicks: "50", ctr: "5.0", cpc: "0.21", cpm: "10.5",
        actions: [ purchase, { action_type: "omni_purchase", value: "3" }, { action_type: "link_click", value: "40" } ],
        action_values: [ { action_type: "purchase", value: "90" }, { action_type: "omni_purchase", value: "90" } ], date_start: "2026-11-03", date_stop: "2026-11-03" } ]
  end
  let(:ad_rows) do
    [ { campaign_id: "111", campaign_name: "Summer", adset_id: "222", adset_name: "Casa 18-35", ad_id: "333", ad_name: "Video Chaussure Alpha", spend: "6.00", impressions: "600",
        reach: "500", clicks: "30", actions: [ purchase ], action_values: [ { action_type: "purchase", value: "60" } ], date_start: "2026-11-03", date_stop: "2026-11-03" },
      { campaign_id: "111", campaign_name: "Summer", adset_id: "222", adset_name: "Casa 18-35", ad_id: "444", ad_name: "Image Alpha", spend: "4.50", impressions: "400",
        reach: "300", clicks: "20", date_start: "2026-11-03", date_stop: "2026-11-03" } ]
  end
  let(:transport) do
    lambda do |uri, _request|
      params = Rack::Utils.parse_nested_query(uri.query)
      requests << params.merge("path" => uri.path)
      meta_reply({ data: params["level"] == "ad" ? ad_rows : campaign_rows }, headers: headers)
    end
  end

  def sync(at: now)
    travel_to(at) { described_class.new(ad_account: account.reload, transport: transport, fx: fx, now: at).call }
  end

  it "backfills the last 30 days at campaign and ad level, with names, ids and daily breakdown" do
    expect(sync).to eq(3)

    insight_requests = requests.select { |request| request["path"].end_with?("/insights") }
    expect(insight_requests.map { |request| request["level"] }).to eq(%w[campaign ad])
    expect(requests.map { |request| request["path"] }).to include(
      "/#{MetaAds::Config.api_version}/act_1001/campaigns",
      "/#{MetaAds::Config.api_version}/act_1001/adsets",
      "/#{MetaAds::Config.api_version}/act_1001/ads",
      "/#{MetaAds::Config.api_version}/act_1001/insights"
    )
    expect(insight_requests).to all(include("time_increment" => "1"))
    expect(JSON.parse(insight_requests.first["time_range"])).to eq("since" => "2026-10-05", "until" => "2026-11-04")
    fields = insight_requests.last["fields"].split(",")
    expect(fields).to include("campaign_id", "campaign_name", "adset_id", "adset_name", "ad_id", "ad_name", "spend", "impressions", "clicks", "actions")

    campaign = MetaAds::DailyInsight.find_by!(level: "campaign")
    expect(campaign).to have_attributes(date: Date.new(2026, 11, 3), spend: 10.5, impressions: 1000, clicks: 50, conversions: 3, conversion_value: 90, currency: "EUR",
      meta_campaign_id: "111", campaign_name: "Summer", ad_id: nil)
    expect(campaign.roas).to eq((BigDecimal("90") / BigDecimal("10.5")).round(4))
    ad = MetaAds::DailyInsight.find_by!(level: "ad", meta_ad_id: "333")
    expect(ad).to have_attributes(meta_adset_id: "222", adset_name: "Casa 18-35", ad_name: "Video Chaussure Alpha", spend: 6, conversions: 3, store_id: store.id)
    expect(ad.ad.name).to eq("Video Chaussure Alpha")
    expect(ad.ad_set.campaign.name).to eq("Summer")
    expect(MetaAds::Ad.where(store: store).pluck(:meta_id)).to match_array(%w[333 444])
    expect(account.reload).to have_attributes(sync_status: "ok", retry_count: 0, last_error_code: nil, insights_backfilled_at: now, last_synced_at: now)
    expect(account.next_sync_at).to eq(now + 1.hour)
  end

  it "keeps spend in the account currency and converts it to the store's currency with the rate and its date" do
    sync
    row = MetaAds::DailyInsight.find_by!(level: "campaign")
    expect(row).to have_attributes(spend: BigDecimal("10.5"), currency: "EUR", display_currency: "MAD", fx_rate: BigDecimal("10.8"), fx_date: Date.new(2026, 11, 3))
    expect(row.spend_display).to eq(BigDecimal("113.4"))
    expect(rate_fetches).to eq([ "EUR" ])
    expect(ExchangeRate.find_by!(base_currency: "EUR", quote_currency: "MAD")).to have_attributes(rate: BigDecimal("10.8"), source: "open.er-api.com")
  end

  it "uses rate 1 when the account already is in the store's currency" do
    account.update!(currency: "MAD")
    sync
    expect(MetaAds::DailyInsight.find_by!(level: "campaign")).to have_attributes(spend_display: BigDecimal("10.5"), fx_rate: 1, fx_date: Date.new(2026, 11, 3), display_currency: "MAD")
    expect(rate_fetches).to be_empty
  end

  it "re-syncs yesterday and today only, updating the same rows instead of duplicating them" do
    sync
    expect { sync(at: now + 1.hour) }.not_to change(MetaAds::DailyInsight, :count)
    insight_requests = requests.select { |request| request["path"].end_with?("/insights") }
    expect(JSON.parse(insight_requests[-2]["time_range"])).to eq("since" => "2026-11-03", "until" => "2026-11-04")

    campaign_rows.first[:spend] = "12.00"
    campaign_rows.first[:actions] = [ { action_type: "purchase", value: "4" } ]
    expect { sync(at: now + 2.hours) }.not_to change(MetaAds::DailyInsight, :count)
    expect(MetaAds::DailyInsight.find_by!(level: "campaign")).to have_attributes(spend: BigDecimal("12"), conversions: 4, spend_display: BigDecimal("129.6"))
    expect(MetaAds::Campaign.where(store: store).count).to eq(1)
  end

  it "follows the ad account's own timezone to decide what today is" do
    account.update!(timezone_name: "America/Los_Angeles")
    sync(at: Time.utc(2026, 11, 4, 3, 0, 0))
    insight = requests.find { |request| request["path"].end_with?("/insights") }
    expect(JSON.parse(insight["time_range"])["until"]).to eq("2026-11-03")
  end

  it "leaves the conversion empty when no rate can be had and fills it in on the next sync" do
    offline = MetaAds::Fx.new(fetcher: ->(_base) { nil })
    travel_to(now) { described_class.new(ad_account: account.reload, transport: transport, fx: offline, now: now).call }
    expect(MetaAds::DailyInsight.where(spend_display: nil).count).to eq(3)
    expect(MetaAds::DailyInsight.pluck(:fx_rate, :fx_date, :display_currency).flatten.compact).to be_empty

    sync(at: now + 1.hour)
    expect(MetaAds::DailyInsight.where(spend_display: nil)).to be_empty
    expect(MetaAds::DailyInsight.find_by!(level: "campaign").spend_display).to eq(BigDecimal("113.4"))
  end

  it "ignores rows with an invalid date or id" do
    campaign_rows << campaign_rows.first.merge(campaign_id: "not-an-id") << campaign_rows.first.merge(date_start: "garbage")
    expect(sync).to eq(3)
  end

  it "does nothing for an account that is not selected or whose connection needs reconnecting" do
    account.update!(selected: false)
    expect(sync).to be_nil
    expect(requests).to be_empty
  end

  it "stops syncing and marks the connection for reconnection on an invalid token (190)" do
    other = MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_2002", name: "Other", currency: "EUR", timezone_name: "UTC", account_status: 1, selected: true)
    expired = ->(_uri, _request) { meta_reply({ error: { code: 190, message: "Error validating access token" } }, status: 400) }
    travel_to(now) { described_class.new(ad_account: account.reload, transport: expired, fx: fx, now: now).call }

    expect(connection.reload).to have_attributes(status: "needs_reauthorization", access_token: nil, last_error_code: "invalid_token")
    expect([ account, other ].map { |record| record.reload.sync_status }).to all(eq("needs_reauthorization"))
    expect([ account, other ].map { |record| record.reload.next_sync_at }).to all(be_nil)
    expect(MetaAds::DailyInsight.count).to eq(0)
    expect(sync).to be_nil
  end

  it "backs off exponentially when Meta rate limits or fails, then recovers" do
    limited = ->(_uri, _request) { meta_reply({ error: { code: 17, message: "User request limit reached" } }, status: 400) }
    delays = 3.times.map do |attempt|
      at = now + attempt.hours
      travel_to(at) { described_class.new(ad_account: account.reload, transport: limited, fx: fx, now: at).call }
      expect(account.reload).to have_attributes(sync_status: "rate_limited", retry_count: attempt + 1, last_error_code: "rate_limited")
      (account.next_sync_at - at).to_i
    end
    expect(delays).to eq([ 60, 120, 240 ])

    down = ->(_uri, _request) { meta_reply({}, status: 503) }
    travel_to(now + 5.hours) { described_class.new(ad_account: account.reload, transport: down, fx: fx, now: now + 5.hours).call }
    expect(account.reload).to have_attributes(sync_status: "failed", retry_count: 4)

    expect(sync(at: now + 6.hours)).to eq(3)
    expect(account.reload).to have_attributes(sync_status: "ok", retry_count: 0, last_error_code: nil)
  end

  it "waits as long as Meta asks when it reports the time to regain access" do
    usage = { "123" => [ { "call_count" => 100, "estimated_time_to_regain_access" => 7 } ] }.to_json
    limited = ->(_uri, _request) { meta_reply({ error: { code: 80004, message: "limit" } }, status: 400, headers: { "x-business-use-case-usage" => usage }) }
    travel_to(now) { described_class.new(ad_account: account.reload, transport: limited, fx: fx, now: now).call }
    expect(account.reload.next_sync_at).to eq(now + 7.minutes)
  end

  it "slows down when Meta's usage headers are high" do
    headers["x-app-usage"] = { call_count: 82, total_cputime: 10, total_time: 12 }.to_json
    sync
    expect(account.reload.next_sync_at).to eq(now + 15.minutes)
  end

  it "never writes the access token anywhere it logs or stores" do
    sync
    expect(requests.to_s).not_to include("synthetic-sync-token")
    expect(MetaAds::DailyInsight.all.map(&:attributes).to_s).not_to include("synthetic-sync-token")
    expect(account.reload.attributes.to_s).not_to include("synthetic-sync-token")
  end
end
