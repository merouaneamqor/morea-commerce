# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant MCP Black Friday theme tools", type: :request do
  let!(:store) do
    Store.create!(
      slug: "mcp-bf-#{SecureRandom.hex(4)}",
      name: "Synthetic BF MCP",
      currency: "MAD",
      subscription_required: false,
      storefront_enabled: true
    )
  end
  let!(:other) do
    Store.create!(
      slug: "mcp-bf-other-#{SecureRandom.hex(4)}",
      name: "Other BF MCP",
      currency: "MAD",
      subscription_required: false,
      storefront_enabled: true
    )
  end
  let(:token) { store.generate_api_token! }

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

  it "lists get_theme and set_black_friday_theme" do
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      headers: mcp_headers,
      as: :json
    names = response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }
    expect(names).to include("get_theme", "set_black_friday_theme")
  end

  it "reads the default theme and toggles Black Friday idempotently for the token store only" do
    payload = call_tool("get_theme")
    expect(payload.dig("data", "storeSettings", "blackFridayTheme")).to eq(false)

    on = call_tool("set_black_friday_theme", { "enabled" => true })
    expect(on.dig("data", "setBlackFridayTheme", "settings", "blackFridayTheme")).to eq(true)
    expect(on.dig("data", "setBlackFridayTheme", "errors")).to eq([])
    expect(store.reload.black_friday_theme).to be(true)
    expect(other.reload.black_friday_theme).to be(false)

    again = call_tool("set_black_friday_theme", { "enabled" => true })
    expect(again.dig("data", "setBlackFridayTheme", "settings", "blackFridayTheme")).to eq(true)

    off = call_tool("set_black_friday_theme", { "enabled" => false })
    expect(off.dig("data", "setBlackFridayTheme", "settings", "blackFridayTheme")).to eq(false)
    expect(store.reload.black_friday_theme).to be(false)
  end

  it "exposes blackFridayTheme on get_store_settings" do
    store.update!(black_friday_theme: true)
    payload = call_tool("get_store_settings")
    expect(payload.dig("data", "storeSettings", "blackFridayTheme")).to eq(true)
  end
end
