# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storefront::SizeAdvisor do
  let(:menswear_chart) do
    {
      "profile" => "menswear",
      "cut" => "regular",
      "garment" => "tops",
      "rows" => Storefront::SizeChart::DEFAULTS["menswear"]
    }
  end

  let(:womenswear_chart) do
    {
      "profile" => "womenswear",
      "cut" => "regular",
      "garment" => "tops",
      "rows" => Storefront::SizeChart::DEFAULTS["womenswear"]
    }
  end

  let(:unisex_chart) do
    {
      "profile" => "unisex",
      "cut" => "regular",
      "garment" => "tops",
      "rows" => Storefront::SizeChart::DEFAULTS["unisex"]
    }
  end

  def recommend(chart, height_cm:, weight_kg:, body_shape: "average", fit_preference: "regular")
    described_class.recommend(
      chart: chart,
      height_cm: height_cm,
      weight_kg: weight_kg,
      body_shape: body_shape,
      fit_preference: fit_preference
    )
  end

  it "recommends M for a typical menswear average build" do
    result = recommend(menswear_chart, height_cm: 175, weight_kg: 72)

    expect(result.verdict).to eq("best").or eq("between")
    expect(result.size).to eq("M")
    expect(result.body["chest"]).to be_between(90, 105)
    expect(result.target["chest"]).to be > result.body["chest"]
    expect(result.reasons).not_to be_empty
  end

  it "recommends L for a taller heavier menswear average build" do
    result = recommend(menswear_chart, height_cm: 180, weight_kg: 85)

    expect(result.size).to eq("L")
  end

  it "recommends S for a lighter menswear build" do
    result = recommend(menswear_chart, height_cm: 170, weight_kg: 65)

    expect(result.size).to eq("S")
  end

  it "leans larger for a broad build and relaxed preference" do
    average = recommend(menswear_chart, height_cm: 175, weight_kg: 72, body_shape: "average", fit_preference: "regular")
    roomy = recommend(menswear_chart, height_cm: 175, weight_kg: 72, body_shape: "broad", fit_preference: "relaxed")

    average_rank = ProductVariant.size_rank(average.size)
    roomy_rank = ProductVariant.size_rank(roomy.size)
    expect(roomy_rank).to be >= average_rank
  end

  it "sizes up for oversized cut versus regular on the same body" do
    regular = recommend(menswear_chart, height_cm: 175, weight_kg: 72)
    oversized = recommend(menswear_chart.merge("cut" => "oversized"), height_cm: 175, weight_kg: 72)

    expect(ProductVariant.size_rank(oversized.size)).to be > ProductVariant.size_rank(regular.size)
  end

  it "recommends S for a typical womenswear average build" do
    result = recommend(womenswear_chart, height_cm: 165, weight_kg: 58)

    expect(result.size).to eq("S")
  end

  it "recommends M for a mid womenswear build" do
    result = recommend(womenswear_chart, height_cm: 170, weight_kg: 65)

    expect(result.size).to eq("M")
  end

  it "recommends M on the unisex default chart for an average adult" do
    result = recommend(unisex_chart, height_cm: 175, weight_kg: 72)

    expect(result.size).to eq("M")
  end

  it "scores bottoms on waist and hips, not chest" do
    bottoms = menswear_chart.merge(
      "garment" => "bottoms",
      "rows" => [
        { "size" => "S", "waist" => 86, "hips" => 98, "length" => 68 },
        { "size" => "M", "waist" => 92, "hips" => 104, "length" => 70 },
        { "size" => "L", "waist" => 98, "hips" => 110, "length" => 72 }
      ]
    )
    result = recommend(bottoms, height_cm: 175, weight_kg: 72)

    expect(%w[S M]).to include(result.size)
    expect(result.reasons.map { |reason| reason["measure"] }).not_to include("chest")
  end

  it "returns none when the chart is empty" do
    result = recommend({ "rows" => [] }, height_cm: 170, weight_kg: 70)

    expect(result.verdict).to eq("none")
    expect(result.size).to be_nil
  end

  it "ignores invalid shape and fit keys without raising" do
    result = recommend(menswear_chart, height_cm: 175, weight_kg: 72, body_shape: "unknown", fit_preference: "snug")

    expect(result.size).to eq("M")
  end

  it "clamps extreme BMI instead of recommending the largest size for light tall builds" do
    light = recommend(menswear_chart, height_cm: 190, weight_kg: 70, body_shape: "slim")
    heavy = recommend(menswear_chart, height_cm: 170, weight_kg: 120, body_shape: "broad")

    expect(%w[XS S M]).to include(light.size)
    expect(ProductVariant.size_rank(heavy.size)).to be >= ProductVariant.size_rank("L")
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

  it "filters default unisex rows to the product sizes" do
    payload = described_class.for(product)
    expect(payload["rows"].map { |row| row["size"] }).to eq(%w[S M L])
    expect(payload["profile"]).to eq("unisex")
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

  it "normalizes blank profile to unisex" do
    expect(described_class.normalize({})["profile"]).to eq("unisex")
  end

  it "exposes a unisex default catalog" do
    expect(described_class::DEFAULTS["unisex"].map { |row| row["size"] }).to eq(%w[XS S M L XL XXL])
  end
end
