# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::McpCapability do
  let(:store) { Store.create!(slug: "mcp-cap-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }

  it "is ready when ads_mcp_management and ads_read are granted" do
    connection = MetaAds::Connection.create!(
      store: store,
      access_token: "token",
      granted_scopes: %w[ads_read business_management ads_mcp_management]
    )
    expect(described_class.ready?(connection)).to be(true)
    expect(described_class.missing_scopes(connection)).to be_empty
  end

  it "reports missing MCP scopes without failing Graph-only connections" do
    connection = MetaAds::Connection.create!(
      store: store,
      access_token: "token",
      granted_scopes: %w[ads_read business_management]
    )
    expect(described_class.ready?(connection)).to be(false)
    expect(described_class.missing_scopes(connection)).to include("ads_mcp_management")
  end

  it "strips the act_ prefix for MCP ad account ids" do
    expect(described_class.numeric_ad_account_id("act_123")).to eq("123")
    expect(described_class.numeric_ad_account_id("123")).to eq("123")
  end
end
