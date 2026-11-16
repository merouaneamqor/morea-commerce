# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant MCP size chart", type: :request do
  let!(:store) do
    Store.create!(
      slug: "mcp-chart-#{SecureRandom.hex(4)}",
      name: "Synthetic MCP chart store",
      currency: "MAD",
      subscription_required: false
    )
  end
  let(:token) { store.generate_api_token! }
  let!(:product) do
    store.products.create!(
      slug: "essential-set",
      name: "Essential Set",
      price_cents: 32_900,
      stock: 0,
      status: "active",
      track_inventory: true
    )
  end

  before do
    host! Store.base_domain
    %w[S M].each do |size|
      product.product_variants.create!(option1_value: size, option2_value: "Noir", stock: 2, active: true)
    end
  end

  def call_tool(name, arguments = {})
    post "/mcp",
         params: {
           jsonrpc: "2.0",
           id: name,
           method: "tools/call",
           params: { name: name, arguments: arguments }
         },
         headers: {
           "Authorization" => "Bearer #{token}",
           "Accept" => "application/json",
           "Content-Type" => "application/json"
         },
         as: :json
    expect(response).to have_http_status(:ok), -> { response.body }
    body = response.parsed_body
    expect(body.dig("error", "code")).not_to eq(-32603)
    expect(body.dig("result", "isError")).not_to eq(true), -> { body.inspect }
    body
  end

  it "updates sizeChart through update_product and returns it on get_product" do
    chart = {
      "profile" => "unisex",
      "cut" => "regular",
      "basis" => "flat",
      "parts" => [
        {
          "key" => "top",
          "label" => "Haut",
          "garment" => "tops",
          "rows" => [
            { "size" => "S", "chest" => 54, "waist" => 58, "length" => 83 },
            { "size" => "M", "chest" => 56, "waist" => 60, "length" => 84 }
          ]
        },
        {
          "key" => "bottom",
          "label" => "Pantalon",
          "garment" => "bottoms",
          "rows" => [
            { "size" => "S", "waist" => 30, "hips" => 55, "length" => 107 },
            { "size" => "M", "waist" => 32, "hips" => 57, "length" => 108 }
          ]
        }
      ]
    }

    updated = call_tool("update_product", { "slug" => "essential-set", "sizeChart" => chart })
    text = updated.dig("result", "content", 0, "text")
    expect(text).to include("Haut")
    expect(text).to include("Pantalon")
    expect(text).to include('"basis":"flat"')

    shown = call_tool("get_product", { "slug" => "essential-set" })
    payload = JSON.parse(shown.dig("result", "content", 0, "text"))
    product_json = payload.dig("data", "product")
    expect(product_json.dig("sizeChart", "basis")).to eq("flat")
    expect(product_json.dig("sizeGuide", "advisor_parts", 0, "rows").find { |row| row["size"] == "S" }["chest"]).to eq(108)
    expect(product.reload.size_chart["parts"].map { |part| part["label"] }).to eq(%w[Haut Pantalon])
  end
end
