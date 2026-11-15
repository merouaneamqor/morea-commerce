# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant MCP Meta Ads tools", type: :request do
  let!(:store) do
    Store.create!(
      slug: "mcp-meta-#{SecureRandom.hex(4)}",
      name: "Synthetic Meta MCP",
      currency: "MAD",
      subscription_required: false,
      storefront_enabled: true
    )
  end
  let(:token) { store.generate_api_token! }
  let!(:connection) do
    MetaAds::Connection.create!(
      store: store,
      access_token: "synthetic-meta-token",
      status: "active",
      granted_scopes: %w[ads_read ads_mcp_management business_management]
    )
  end
  let(:calls) { [] }
  let(:transport) do
    lambda do |_uri, request|
      calls << JSON.parse(request.body)
      body = case JSON.parse(request.body)["method"]
      when "tools/list"
        { jsonrpc: "2.0", id: "1", result: { tools: [ { name: "ads_get_ad_entities", description: "Report" } ] } }
      when "tools/call"
        { jsonrpc: "2.0", id: "2", result: { content: [ { type: "text", text: { data: [ { id: "9", name: "X" } ] }.to_json } ] } }
      else
        raise "unexpected"
      end
      Struct.new(:code, :body, :to_hash).new("200", body.to_json, {})
    end
  end

  before do
    host! Store.base_domain
    allow(MetaAds::McpClient).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: transport) }
  end

  def mcp_headers(secret = token)
    {
      "Authorization" => "Bearer #{secret}",
      "Accept" => "application/json",
      "Content-Type" => "application/json"
    }
  end

  def call_tool(name, arguments = {})
    post "/mcp",
      params: {
        jsonrpc: "2.0",
        id: name,
        method: "tools/call",
        params: { name: name, arguments: arguments }
      },
      headers: mcp_headers,
      as: :json
    expect(response).to have_http_status(:ok), -> { response.body }
    body = response.parsed_body
    expect(body.dig("result", "isError")).not_to eq(true), -> { body.inspect }
    JSON.parse(body.dig("result", "content", 0, "text"))
  end

  it "lists Meta Ads MCP proxy tools" do
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      headers: mcp_headers,
      as: :json
    names = response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }
    expect(names).to include("meta_ads_status", "meta_ads_list_mcp_tools", "meta_ads_call_mcp_tool")
  end

  it "returns meta_ads_status without tokens" do
    payload = call_tool("meta_ads_status")
    expect(payload["connected"]).to be(true)
    expect(payload["mcpReady"]).to be(true)
    expect(payload.to_json).not_to include("synthetic-meta-token")
  end

  it "proxies tools/list and tools/call to Meta Ads MCP" do
    listed = call_tool("meta_ads_list_mcp_tools")
    expect(listed["tools"].map { |tool| tool["name"] }).to include("ads_get_ad_entities")

    called = call_tool("meta_ads_call_mcp_tool", {
      tool: "ads_get_ad_entities",
      arguments: { ad_account_id: "11", fields: %w[id name], date_preset: "last_7d" }
    })
    expect(called.dig("result", "data", 0, "name")).to eq("X")
    expect(calls.map { |call| call["method"] }).to include("tools/list", "tools/call")
  end

  it "requires confirm for non-read Meta Ads MCP tools" do
    post "/mcp",
      params: {
        jsonrpc: "2.0",
        id: "write",
        method: "tools/call",
        params: { name: "meta_ads_call_mcp_tool", arguments: { tool: "ads_create_campaign", arguments: {} } }
      },
      headers: mcp_headers,
      as: :json
    body = response.parsed_body
    expect(body.dig("result", "isError")).to eq(true)
    text = JSON.parse(body.dig("result", "content", 0, "text"))
    expect(text["code"]).to eq("confirm_required")
  end
end
