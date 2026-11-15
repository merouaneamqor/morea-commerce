# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Storefront size advisor", type: :request do
  let(:store) do
    Store.create!(
      slug: "fit-#{SecureRandom.hex(4)}",
      name: "Fit Store",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  let!(:product) do
    store.products.create!(
      name: "Solo Fleece",
      slug: "solo-fleece",
      status: "active",
      price_cents: 75_000,
      stock: 0,
      track_inventory: true
    )
  end

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    %w[S M L XL].each do |size|
      product.product_variants.create!(
        option1_value: size,
        option2_value: "Total Black",
        stock: 5,
        active: true
      )
    end
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "shows Find my size and the advisor shell on products with sizes" do
    get "/en/products/solo-fleece"

    expect(response).to have_http_status(:ok)
    expect(document.at_css("button.size-advisor-trigger")&.text).to include("Find my size")
    shell = document.at_css(".size-advisor")
    expect(shell).to be_present
    expect(shell["aria-hidden"]).to eq("true")
    root = document.at_css("[data-controller~='size-advisor']")
    expect(root).to be_present
    expect(root["data-controller"]).to include("variant-picker")
    chart = JSON.parse(root["data-size-advisor-chart-value"])
    expect(chart["rows"].map { |row| row["size"] }).to include("S", "M", "L", "XL")
    expect(document.at_css("#size-advisor-title").text).to include("Size advisor")
  end

  it "hides the advisor when the product has no size variants" do
    plain = store.products.create!(
      name: "Candle",
      slug: "candle",
      status: "active",
      price_cents: 20_000,
      stock: 3
    )

    get "/en/products/#{plain.slug}"

    expect(response).to have_http_status(:ok)
    expect(document.at_css(".size-advisor-trigger")).to be_nil
    expect(document.at_css(".size-advisor")).to be_nil
  end

  it "localizes the trigger in French" do
    get "/fr/products/solo-fleece"

    expect(response).to have_http_status(:ok)
    expect(document.at_css("button.size-advisor-trigger").text).to include("Trouver ma taille")
  end
end
