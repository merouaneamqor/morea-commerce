# frozen_string_literal: true

require "rails_helper"
require "nokogiri"
require "base64"

RSpec.describe "Storefront pages", type: :request do
  let(:store) do
    Store.create!(
      slug: "pages-#{SecureRandom.hex(4)}",
      name: "Pages Store",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  before { host! "#{store.slug}.#{Store.base_domain}" }

  def document
    Nokogiri::HTML(response.body)
  end

  it "paints a content page without hiding the title behind the entrance animation" do
    store.pages.create!(
      slug: "story",
      title: "Our story",
      body: "A page long enough to be the largest paint.",
      published: true,
      template: "content"
    )

    get "/en/pages/story"

    expect(response).to have_http_status(:ok)
    title = document.at_css("h1.store-page__title")
    expect(title.text).to eq("Our story")
    expect(title.ancestors.any? { |node| node["data-controller"].to_s.split.include?("reveal") }).to be(false)
    expect(document.at_css('link[href*="fonts.googleapis.com"]')).to be_nil
    preload = document.at_css('link[rel="preload"][as="font"][href*="dm-sans"]')
    expect(preload["type"]).to eq("font/woff2")
    expect(preload["crossorigin"]).to eq("anonymous")
    expect(response.body).to include("fonts")
  end

  it "preloads a landing hero with the same candidate the image will use" do
    page = store.pages.create!(slug: "launch", title: "Launch", body: "Landing", published: true, template: "landing")
    page.page_sections.create!(
      kind: "hero",
      position: 1,
      visible: true,
      heading: "Move",
      settings: { "image_url" => "https://images.unsplash.com/photo-1" }
    )

    get "/en/pages/launch"

    expect(response).to have_http_status(:ok)
    preload = document.at_css('link[rel="preload"][as="image"]')
    expect(preload["imagesizes"]).to eq("100vw")
    expect(preload["imagesrcset"]).to include("1920w")
    expect(preload["fetchpriority"]).to eq("high")
    image = document.at_css("img")
    expect(image["fetchpriority"]).to eq("high")
    expect(image["loading"]).to eq("eager")
    expect(image["srcset"]).to eq(preload["imagesrcset"])
  end

  it "does not hide the product photo behind the entrance animation" do
    store.products.create!(
      name: "Essential Set",
      slug: "essential-set",
      status: "active",
      price_cents: 89_900,
      stock: 4
    )

    get "/fr/products/essential-set"

    expect(response).to have_http_status(:ok)
    gallery = document.at_css(".pdp__gallery")
    expect(gallery["data-controller"].to_s).not_to include("reveal")
    expect(document.at_css('link[rel="preconnect"][href="https://res.cloudinary.com"]')).to be_present
    expect(document.at_css('link[href*="fonts.googleapis.com"]')).to be_nil
    expect(document.at_css('link[rel="preload"][as="font"][href*="dm-sans"]')).to be_present
  end

  it "paints the selected color's photos on first load and keeps product photos for fallback" do
    product = store.products.create!(
      name: "Color Set",
      slug: "color-set",
      status: "active",
      price_cents: 12_000,
      track_inventory: false
    )
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN9sAAAAASUVORK5CYII=")
    product.images.attach(io: StringIO.new(png), filename: "product.png", content_type: "image/png")
    black = product.product_variants.create!(option1_value: "S", option2_value: "Black", stock: 2)
    white = product.product_variants.create!(option1_value: "S", option2_value: "White", stock: 2)
    black.images.attach(io: StringIO.new(png), filename: "black.png", content_type: "image/png")

    get "/en/products/color-set"

    expect(response).to have_http_status(:ok)
    root = document.at_css("[data-controller~='variant-gallery']")
    expect(root["data-controller"]).to include("variant-picker")
    product_urls = JSON.parse(root["data-variant-gallery-product-images-value"])
    expect(product_urls).not_to be_empty
    payload = JSON.parse(root["data-variant-picker-variants-value"])
    by_id = payload.index_by { |variant| variant["id"] }
    expect(by_id.fetch(black.id)["images"]).to be_present
    expect(by_id.fetch(white.id)["images"]).to be_nil
    # Size is required on the PDP: variant id stays empty until the shopper picks one.
    expect(document.at_css("input[name='product_variant_id']")["value"]).to eq("")
    expect(document.at_css("#pdp-sizes")).to be_present
    lead = document.at_css(".pdp__gallery img")["src"]
    black_key = by_id.fetch(black.id)["images"].first.to_s.split("?").first.split("/").last
    product_key = product_urls.first.to_s.split("?").first.split("/").last
    expect(lead).to include(black_key)
    expect(lead).not_to include(product_key) if black_key != product_key
  end

  it "maps product gallery filenames onto colors that have no variant photos" do
    product = store.products.create!(
      name: "Filename Colors",
      slug: "filename-colors",
      status: "active",
      price_cents: 9_000,
      track_inventory: false
    )
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN9sAAAAASUVORK5CYII=")
    product.images.attach(io: StringIO.new(png), filename: "pink-main.png", content_type: "image/png")
    product.images.attach(io: StringIO.new(png), filename: "black-hero.png", content_type: "image/png")
    product.images.attach(io: StringIO.new(png), filename: "studio-wide.png", content_type: "image/png")
    pink = product.product_variants.create!(option1_value: "S", option2_value: "Pink", stock: 2)
    black = product.product_variants.create!(option1_value: "S", option2_value: "Black", stock: 2)
    white = product.product_variants.create!(option1_value: "S", option2_value: "White", stock: 2)

    get "/en/products/filename-colors"

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(document.at_css("[data-variant-picker-variants-value]")["data-variant-picker-variants-value"])
    by_id = payload.index_by { |variant| variant["id"] }
    expect(by_id.fetch(pink.id)["images"].join).to include("pink-main")
    expect(by_id.fetch(black.id)["images"].join).to include("black-hero")
    expect(by_id.fetch(white.id)["images"]).to be_nil
    # Initial variant sorts by size then color, so Black leads and the SSR
    # gallery follows its filename mapping. Variant id stays empty until size pick.
    expect(document.at_css("input[name='product_variant_id']")["value"]).to eq("")
    expect(document.at_css(".pdp__gallery img")["src"]).to include("black-hero")
  end

  it "shows the mobile offer block, savings, and a size-gated sticky CTA" do
    product = store.products.create!(
      name: "Basic Tracksuit",
      slug: "basic-tracksuit",
      status: "active",
      price_cents: 38_900,
      compare_at_cents: 44_900,
      currency: "DH",
      track_inventory: false
    )
    product.product_variants.create!(option1_value: "M", option2_value: "Noir", stock: 0)
    product.product_variants.create!(option1_value: "L", option2_value: "Noir", stock: 0)
    store.pages.create!(slug: "returns", title: "Retours", body: "7 jours", published: true, template: "content")

    get "/fr/products/basic-tracksuit"

    expect(response).to have_http_status(:ok)
    expect(document.at_css(".pdp__offer")).to be_present
    expect(document.at_css(".pdp__price").text).to include("389")
    expect(document.at_css(".pdp__price-compare").text).to include("449")
    expect(document.at_css(".pdp__promo-badge").text).to match(/promotion/i)
    expect(document.at_css(".pdp__offer-save").text).to include("60")
    expect(document.at_css(".pdp__offer-save").text).to match(/économie/i)
    expect(document.at_css(".pdp__offer-until")).to be_nil
    expect(document.at_css(".pdp__ship-note-lead").text).to include("Frais d")
    expect(document.at_css("input[name='product_variant_id']")["value"]).to eq("")
    expect(document.at_css("#pdp-sizes .landing-buy__label").text).to include("Taille")
    expect(document.at_css(".mobile-buy-bar .pdp-order-btn__sub").text).to include("Aucun paiement en ligne")
    expect(document.at_css(".mobile-buy-bar [data-variant-picker-target='orderLabel']").text).to include("Choisir ma taille")
    expect(document.css(".mobile-buy-bar button").size).to eq(1)
    expect(document.at_css("[data-variant-picker-target='selectionSummary']")).to be_present
    expect(document.at_css(".size-sheet")).to be_present
    expect(document.at_css("#size-sheet-title").text).to include("Quelle taille")
    expect(document.css(".size-sheet [data-variant-picker-target='sheetSizeButton']").map { |n| n.text.strip }).to include("M", "L")
    expect(document.at_css(".pdp__trust").text).to include("Livraison partout au Maroc")
    expect(document.at_css(".pdp__trust-link").text).to include("Retours")
    expect(response.body).not_to match(/Plus que \d+/i)
  end

  it "shows timed sale copy when sale_ends_at is still in the future" do
    product = store.products.create!(
      name: "Sale Set",
      slug: "sale-set",
      status: "active",
      price_cents: 38_900,
      compare_at_cents: 44_900,
      currency: "DH",
      track_inventory: false,
      sale_ends_at: 2.days.from_now.change(hour: 23, min: 59)
    )

    get "/fr/products/sale-set"

    expect(response).to have_http_status(:ok)
    until_copy = document.at_css(".pdp__offer-until")
    expect(until_copy).to be_present
    expect(until_copy.text).to include("449")
    expect(until_copy.text).to match(/repasse/i)
    expect(document.at_css(".pdp__offer-save").attributes).to have_key("hidden")
  end

  it "reverts the storefront price after sale_ends_at" do
    product = store.products.create!(
      name: "Ended Sale",
      slug: "ended-sale",
      status: "active",
      price_cents: 38_900,
      compare_at_cents: 44_900,
      currency: "DH",
      track_inventory: false,
      sale_ends_at: 1.hour.ago
    )

    expect(product.sale_expired?).to be(true)
    expect(product.storefront_price_cents).to eq(44_900)
    expect(product.on_sale?).to be(false)

    get "/fr/products/ended-sale"

    expect(response).to have_http_status(:ok)
    expect(document.at_css(".pdp__price").text).to include("449")
    expect(document.at_css(".pdp__price-compare")).to be_nil
    expect(document.at_css(".pdp__offer-save")).to be_nil
    expect(document.at_css(".pdp__offer-until")).to be_nil
  end
end
