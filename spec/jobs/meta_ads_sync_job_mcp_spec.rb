# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAdsSyncJob, "MCP sync path" do
  let(:store) { Store.create!(slug: "mcp-sync-#{SecureRandom.hex(4)}", name: "Synthetic", currency: "MAD") }
  let(:connection) do
    MetaAds::Connection.create!(
      store: store,
      access_token: "token",
      granted_scopes: %w[ads_read ads_mcp_management]
    )
  end
  let(:account) do
    MetaAds::AdAccount.create!(
      store: store,
      connection: connection,
      meta_ad_account_id: "act_99",
      name: "Main",
      currency: "MAD",
      timezone_name: "UTC",
      account_status: 1,
      selected: true
    )
  end

  it "uses McpInsightsSync when the flag is on and scopes allow" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_ADS_SYNC_VIA_MCP").and_return("1")
    expect(MetaAds::McpInsightsSync).to receive(:new).with(hash_including(ad_account: account)).and_return(instance_double(MetaAds::McpInsightsSync, call: 0))
    expect(MetaAds::InsightsSync).not_to receive(:new)

    described_class.new.perform(account.id)
  end

  it "keeps Graph InsightsSync when the flag is off" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_ADS_SYNC_VIA_MCP").and_return(nil)
    expect(MetaAds::InsightsSync).to receive(:new).with(hash_including(ad_account: account)).and_return(instance_double(MetaAds::InsightsSync, call: 0))
    expect(MetaAds::McpInsightsSync).not_to receive(:new)

    described_class.new.perform(account.id)
  end
end
