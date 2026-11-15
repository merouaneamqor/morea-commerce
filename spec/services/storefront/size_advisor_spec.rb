# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storefront::SizeAdvisor do
  let(:chart) do
    {
      "profile" => "menswear",
      "cut" => "regular",
      "garment" => "tops",
      "rows" => [
        { "size" => "S", "chest" => 102, "waist" => 96, "hips" => 100, "length" => 68 },
        { "size" => "M", "chest" => 108, "waist" => 102, "hips" => 106, "length" => 70 },
        { "size" => "L", "chest" => 114, "waist" => 108, "hips" => 112, "length" => 72 },
        { "size" => "XL", "chest" => 120, "waist" => 114, "hips" => 118, "length" => 74 }
      ]
    }
  end

  it "recommends a mid size for average height and weight" do
    result = described_class.recommend(
      chart: chart,
      height_cm: 175,
      weight_kg: 72,
      body_shape: "average",
      fit_preference: "regular"
    )

    expect(%w[best between]).to include(result.verdict)
    expect(%w[S M L XL]).to include(result.size)
    expect(result.reasons).not_to be_empty
    expect(result.body["chest"]).to be_a(Numeric)
  end

  it "leans larger for a broad build and relaxed preference" do
    average = described_class.recommend(
      chart: chart,
      height_cm: 180,
      weight_kg: 85,
      body_shape: "average",
      fit_preference: "regular"
    )
    roomy = described_class.recommend(
      chart: chart,
      height_cm: 180,
      weight_kg: 85,
      body_shape: "broad",
      fit_preference: "relaxed"
    )

    average_rank = ProductVariant.size_rank(average.size)
    roomy_rank = ProductVariant.size_rank(roomy.size)
    expect(roomy_rank).to be >= average_rank
  end

  it "returns none when the chart is empty" do
    result = described_class.recommend(chart: { "rows" => [] }, height_cm: 170, weight_kg: 70)
    expect(result.verdict).to eq("none")
    expect(result.size).to be_nil
  end
end

RSpec.describe Storefront::SizeChart do
  let(:store) { Store.create!(slug: "size-#{SecureRandom.hex(3)}", name: "Size Store", currency: "MAD", storefront_enabled: true) }
  let(:product) do
    store.products.create!(
      name: "Fleece",
      slug: "fleece",
      status: "active",
      price_cents: 75_000,
      stock: 10
    )
  end

  before do
    %w[S M L].each do |size|
      product.product_variants.create!(option1_value: size, option2_value: "Black", stock: 3, active: true)
    end
  end

  it "filters default menswear rows to the product sizes" do
    payload = described_class.for(product)
    expect(payload["rows"].map { |row| row["size"] }).to eq(%w[S M L])
    expect(payload["profile"]).to eq("menswear")
    expect(payload["rows"].first["chest"]).to be_positive
  end

  it "keeps a merchant chart when measurements are present" do
    product.update!(
      size_chart: {
        "profile" => "womenswear",
        "cut" => "oversized",
        "garment" => "tops",
        "rows" => [
          { "size" => "S", "chest" => 91, "waist" => 77, "hips" => 97, "length" => 62 },
          { "size" => "M", "chest" => 96, "waist" => 82, "hips" => 102, "length" => 64 },
          { "size" => "L", "chest" => 102, "waist" => 88, "hips" => 108, "length" => 66 }
        ]
      }
    )

    payload = described_class.for(product)
    expect(payload["profile"]).to eq("womenswear")
    expect(payload["cut"]).to eq("oversized")
    expect(payload["rows"].find { |row| row["size"] == "M" }["chest"]).to eq(96)
  end
end
