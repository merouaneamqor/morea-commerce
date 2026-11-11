# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

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
    font = document.at_css('link[as="style"][href*="fonts.googleapis.com"]')
    expect(font["href"]).to include("display=swap")
    expect(font["rel"]).to eq("preload")
    expect(font["as"]).to eq("style")
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
    font = document.at_css('link[as="style"][href*="fonts.googleapis.com"]')
    expect(font["rel"]).to eq("preload")
  end
end
