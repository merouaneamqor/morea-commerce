# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant MCP funnel tools", type: :request do
  let!(:store) do
    Store.create!(
      slug: "mcp-funnel-#{SecureRandom.hex(4)}",
      name: "Synthetic Funnel MCP",
      currency: "MAD",
      subscription_required: false,
      storefront_enabled: true
    )
  end
  let(:token) { store.generate_api_token! }
  let(:now) { Time.zone.parse("2026-11-15 12:00:00") }

  before { host! Store.base_domain }

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
    expect(body.dig("error", "code")).not_to eq(-32603)
    expect(body.dig("result", "isError")).not_to eq(true), -> { body.inspect }
    JSON.parse(body.dig("result", "content", 0, "text"))
  end

  around do |example|
    travel_to(now) { example.run }
  end

  before do
    store.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: "facebook",
      meta_campaign_id: "12345678901",
      funnel_stage: "ordered",
      landing_path: "/en/?utm_source=facebook",
      landed_at: now - 2.hours,
      last_seen_at: now - 1.hour
    )
    store.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: "tiktok",
      ttclid: "E.1",
      funnel_stage: "checkout_started",
      landing_path: "/fr/products/x",
      landed_at: now - 3.hours,
      last_seen_at: now - 3.hours
    )
  end

  it "lists funnel tools" do
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      headers: mcp_headers,
      as: :json
    names = response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }
    expect(names).to include("funnel_summary", "funnel_sources", "funnel_landings")
  end

  it "returns funnel_summary aggregates for the store window" do
    payload = call_tool("funnel_summary", {
      "since" => "2026-11-01",
      "until" => "2026-11-15",
      "sourcesLimit" => 10,
      "landingsLimit" => 5
    })
    summary = payload.dig("data", "funnelSummary")
    expect(summary.fetch("totalVisits")).to eq(2)
    expect(summary.fetch("stages").map { |row| row["key"] }).to eq(StorefrontVisit::STAGES)
    expect(summary.fetch("sources").map { |row| row["label"] }).to include("meta", "tiktok")
    expect(summary.fetch("landings").size).to be <= 5
    expect(summary.fetch("sourcesLimit")).to eq(10)
    expect(JSON.generate(summary)).not_to include("storefront_funnel_events")
  end

  it "returns funnel_sources and funnel_landings without raw event tables" do
    sources = call_tool("funnel_sources", { "since" => "2026-11-01", "until" => "2026-11-15", "limit" => 10 })
    landings = call_tool("funnel_landings", { "since" => "2026-11-01", "until" => "2026-11-15", "limit" => 5 })

    expect(sources.dig("data", "funnelSummary", "sources")).to be_present
    expect(landings.dig("data", "funnelSummary", "landings")).to be_present
    expect(JSON.generate(sources)).not_to match(/"token"|funnel_events/)
    expect(JSON.generate(landings)).not_to match(/"token"|funnel_events/)
  end

  it "errors when the date window exceeds 366 days" do
    post "/mcp",
      params: {
        jsonrpc: "2.0",
        id: "funnel_summary",
        method: "tools/call",
        params: {
          name: "funnel_summary",
          arguments: { "since" => "2025-01-01", "until" => "2026-11-15" }
        }
      },
      headers: mcp_headers,
      as: :json
    body = response.parsed_body
    text = body.dig("result", "content", 0, "text").to_s
    expect(body.dig("result", "isError") || text).to match(/366|error/i)
  end
end
