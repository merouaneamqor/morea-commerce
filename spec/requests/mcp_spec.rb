# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant MCP", type: :request do
  let!(:store) do
    Store.create!(
      slug: "mcp-store-#{SecureRandom.hex(4)}",
      name: "Synthetic MCP store",
      currency: "MAD",
      subscription_required: false
    )
  end
  let(:token) { store.generate_api_token! }

  before { host! Store.base_domain }

  def mcp_headers(secret = token, accept: "application/json")
    {
      "Authorization" => "Bearer #{secret}",
      "Accept" => accept,
      "Content-Type" => "application/json"
    }
  end

  def post_mcp(body, headers: mcp_headers)
    post "/mcp", params: body, headers: headers, as: :json
  end

  it "rejects unauthenticated GET and POST with a protected-resource challenge" do
    get "/mcp"
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("/.well-known/oauth-protected-resource/mcp")
    expect(response.parsed_body.dig("error", "code")).to eq(-32001)

    post_mcp({ jsonrpc: "2.0", id: 7, method: "tools/list" }, headers: { "Accept" => "application/json", "Content-Type" => "application/json" })
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to include(
      "jsonrpc" => "2.0",
      "id" => 7,
      "error" => hash_including("code" => -32001, "message" => "Unauthorized")
    )
  end

  it "rejects authenticated GET with Allow POST" do
    get "/mcp", headers: mcp_headers
    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to eq("POST")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body.dig("error", "message")).to match(/method not allowed/i)
  end

  it "lists tools over JSON Accept without requiring text/event-stream" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "tools/list" })
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include("tools")
  end

  it "accepts initialize with JSON Accept only" do
    post_mcp({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "synthetic-agent", version: "0.0.1" }
      }
    })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "serverInfo", "name")).to be_present
  end

  it "rejects batched JSON-RPC bodies" do
    post_mcp([ { jsonrpc: "2.0", id: 1, method: "tools/list" } ])
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "message")).to match(/single request object|invalid request/i)
  end

  it "blocks past-due workspaces with 402" do
    store.update!(subscription_required: true, billing_status: "canceled", trial_ends_at: 1.day.ago)
    post_mcp({ jsonrpc: "2.0", id: 9, method: "tools/list" })
    expect(response).to have_http_status(:payment_required)
    expect(response.parsed_body.dig("error", "code")).to eq(-32003)
    expect(response.parsed_body.dig("error", "data", "code")).to eq("subscription_required")
    expect(response.parsed_body["id"]).to eq(9)
  end

  it "rejects platform tokens on the merchant endpoint" do
    owner = User.create!(
      email: "platform-#{SecureRandom.hex(4)}@example.test",
      password: "synthetic-credential-123",
      admin: true,
      super_admin: true
    )
    secret = PlatformApiToken.issue!(user: owner)
    post_mcp({ jsonrpc: "2.0", id: 1, method: "tools/list" }, headers: mcp_headers(secret))
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq(-32001)
  end

  it "answers GET on the token endpoint with Allow POST instead of a routing miss" do
    get "/oauth/token"
    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to include("POST")
    expect(response.parsed_body.fetch("error")).to eq("invalid_request")
  end

  it "reads get_product, list_products and store_stats without JSON-RPC internal errors" do
    product = store.products.create!(
      slug: "basic-tracksuit",
      name: "Basic Tracksuit Morea",
      price_cents: 0,
      stock: 0,
      status: "active",
      track_inventory: true
    )
    product.product_variants.create!(option1_value: "M", option2_value: "Noir", stock: 2, active: true)

    call_tool = lambda do |name, arguments = {}|
      post_mcp({
        jsonrpc: "2.0",
        id: name,
        method: "tools/call",
        params: { name: name, arguments: arguments }
      })
      expect(response).to have_http_status(:ok), -> { response.body }
      body = response.parsed_body
      expect(body.dig("error", "code")).not_to eq(-32603)
      expect(body.dig("result", "isError")).not_to eq(true)
      body
    end

    listed = call_tool.call("list_products", { "limit" => 10 })
    expect(listed.dig("result", "content", 0, "text")).to include("basic-tracksuit")

    shown = call_tool.call("get_product", { "slug" => "basic-tracksuit" })
    expect(shown.dig("result", "content", 0, "text")).to include("Basic Tracksuit")

    stats = call_tool.call("store_stats", {})
    text = stats.dig("result", "content", 0, "text")
    expect(text).to include("placedCount")
    expect(text).to include("pipeline")
  end
end
