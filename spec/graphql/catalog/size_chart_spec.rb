# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog size chart GraphQL", type: :request do
  let!(:store) do
    Store.create!(
      slug: "chart-#{SecureRandom.hex(4)}",
      name: "Chart Store",
      currency: "MAD",
      subscription_required: false
    )
  end
  let(:token) { store.generate_api_token! }
  let!(:product) do
    store.products.create!(
      name: "Essential Set",
      slug: "essential-set",
      status: "active",
      price_cents: 32_900,
      stock: 0,
      track_inventory: true
    )
  end

  before do
    host! Store.base_domain
    %w[S M].each do |size|
      product.product_variants.create!(
        option1_value: size,
        option2_value: "Noir",
        stock: 3,
        active: true
      )
    end
  end

  def graphql(query, variables: {})
    post "/graphql",
         params: { query: query, variables: variables },
         headers: {
           "Authorization" => "Bearer #{token}",
           "Content-Type" => "application/json",
           "Accept" => "application/json"
         },
         as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it "writes a flat two-piece size chart and returns stored plus resolved guide" do
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

    body = graphql(<<~GQL, variables: { slug: "essential-set", sizeChart: chart })
      mutation($slug: String!, $sizeChart: JSON!) {
        updateProduct(slug: $slug, sizeChart: $sizeChart) {
          product { slug sizeChart sizeGuide }
          errors
        }
      }
    GQL

    expect(body.dig("data", "updateProduct", "errors")).to eq([])
    stored = body.dig("data", "updateProduct", "product", "sizeChart")
    guide = body.dig("data", "updateProduct", "product", "sizeGuide")
    expect(stored["basis"]).to eq("flat")
    expect(stored["parts"].map { |part| part["label"] }).to eq(%w[Haut Pantalon])
    expect(guide["parts"].first["rows"].find { |row| row["size"] == "S" }["chest"]).to eq(54)
    expect(guide["advisor_parts"].first["rows"].find { |row| row["size"] == "S" }["chest"]).to eq(108)
    expect(product.reload.size_chart["basis"]).to eq("flat")
  end

  it "clears a size chart back to defaults" do
    product.update!(size_chart: {
      "profile" => "unisex",
      "basis" => "flat",
      "garment" => "tops",
      "rows" => [ { "size" => "S", "chest" => 54, "waist" => 58, "length" => 83 } ]
    })

    body = graphql(<<~GQL, variables: { slug: "essential-set", clearSizeChart: true })
      mutation($slug: String!, $clearSizeChart: Boolean!) {
        updateProduct(slug: $slug, clearSizeChart: $clearSizeChart) {
          product { sizeChart sizeGuide }
          errors
        }
      }
    GQL

    expect(body.dig("data", "updateProduct", "errors")).to eq([])
    expect(body.dig("data", "updateProduct", "product", "sizeChart")["rows"]).to eq([])
    expect(body.dig("data", "updateProduct", "product", "sizeGuide")["rows"].map { |row| row["size"] }).to include("S", "M")
  end
end
