# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::McpClient do
  let(:store) { Store.create!(slug: "meta-mcp-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-meta-token", granted_scopes: %w[ads_read ads_mcp_management]) }
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |uri, request|
      requests << [ uri, request ]
      raise "Unexpected HTTP call" if responses.empty?

      responses.shift
    end
  end
  subject(:client) { described_class.new(connection: connection, transport: transport) }

  def reply(status: 200, body: {}, headers: {})
    Struct.new(:code, :body, :to_hash).new(status.to_s, body.is_a?(String) ? body : body.to_json, headers.transform_values { |value| [ value ] })
  end

  it "lists tools against mcp.facebook.com with a bearer token" do
    responses << reply(body: { jsonrpc: "2.0", id: "1", result: { tools: [ { name: "ads_get_ad_entities" } ] } })

    result = client.list_tools

    uri, request = requests.first
    expect(uri.to_s).to eq("https://mcp.facebook.com/ads")
    expect(request["Authorization"]).to eq("Bearer synthetic-meta-token")
    expect(uri.to_s).not_to include("synthetic-meta-token")
    expect(JSON.parse(request.body)["method"]).to eq("tools/list")
    expect(result.result.dig("tools", 0, "name")).to eq("ads_get_ad_entities")
  end

  it "calls a tool and parses JSON content text" do
    responses << reply(body: {
      jsonrpc: "2.0", id: "2",
      result: { content: [ { type: "text", text: { data: [ { id: "1", name: "Camp" } ] }.to_json } ] }
    })

    result = client.call_tool("ads_get_ad_entities", ad_account_id: "11", fields: %w[id name])

    expect(JSON.parse(requests.first.last.body).dig("params", "name")).to eq("ads_get_ad_entities")
    expect(result.tool_json.dig("data", 0, "name")).to eq("Camp")
  end

  it "parses SSE data frames" do
    payload = { jsonrpc: "2.0", id: "3", result: { tools: [] } }
    responses << reply(
      body: "event: message\ndata: #{payload.to_json}\n\n",
      headers: { "content-type" => "text/event-stream" }
    )

    expect(client.list_tools.result["tools"]).to eq([])
  end

  {
    "unauthorized" => [ 401, MetaAds::McpClient::AuthError ],
    "forbidden" => [ 403, MetaAds::McpClient::PermissionError ],
    "rate limited" => [ 429, MetaAds::McpClient::RateLimitError ],
    "server error" => [ 500, MetaAds::McpClient::TransientError ]
  }.each do |name, (status, error_class)|
    it "maps #{name} to #{error_class.name.demodulize}" do
      responses << reply(status: status, body: { error: "secret synthetic-meta-token" })

      expect { client.list_tools }.to raise_error(error_class) { |error|
        expect(error.message).not_to include("synthetic-meta-token")
      }
    end
  end
end
