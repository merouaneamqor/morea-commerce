# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Storefront search", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:store) do
    Store.create!(
      slug: "search-#{suffix}",
      name: "Synthetic search store",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  def product(workspace: store, **attributes)
    workspace.products.create!({
      name: "Search product #{SecureRandom.hex(4)}",
      slug: "search-product-#{SecureRandom.hex(6)}",
      status: "active",
      price_cents: 10_000,
      stock: 5,
      track_inventory: true
    }.merge(attributes))
  end

  def search(query, locale: "en", **params)
    host! "#{store.slug}.#{Store.base_domain}"
    get "/#{locale}/search", params: { q: query }.merge(params)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def result_names
    document.css("a.home-card").map { |node| node.text.squish }
  end

  it "returns only active matching products from the host tenant" do
    own = product(name: "Shared Linen Jacket", slug: "own-linen-jacket")
    draft = product(name: "Shared Linen Draft", slug: "draft-linen", status: "draft")
    archived = product(name: "Shared Linen Archive", slug: "archived-linen", status: "archived")
    foreign_store = Store.create!(slug: "foreign-#{suffix}", name: "Foreign synthetic store", currency: "MAD")
    foreign = product(workspace: foreign_store, name: "Shared Linen Foreign", slug: "foreign-linen")

    search "Shared Linen"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.name)
    expect(response.body).not_to include(draft.name, archived.name, foreign.name)
    expect(document.at_css("a[href='/en/products/#{own.slug}']")).to be_present
  end

  it "matches and renders a translation in the requested locale" do
    translated = product(name: "Base language tunic", slug: "translated-tunic")
    translated.translations.create!(locale: "ar", name: "سترة أطلسية")
    product(name: "Unrelated active product", slug: "unrelated-product")

    search "أطلسية", locale: "ar"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("سترة أطلسية")
    expect(document.at_css("html")["dir"]).to eq("rtl")
    expect(document.at_css("a[href='/ar/products/#{translated.slug}']")).to be_present
  end

  it "sorts matches by price and can restrict results to available stock" do
    expensive = product(name: "Wool Search Expensive", slug: "wool-expensive", price_cents: 30_000)
    cheap = product(name: "Wool Search Cheap", slug: "wool-cheap", price_cents: 8_000)
    sold_out = product(name: "Wool Search Sold Out", slug: "wool-sold-out", price_cents: 4_000, stock: 0)

    search "Wool Search", sort: "price_asc", in_stock: "1"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(sold_out.name)
    expect(result_names.join(" ")).to include(cheap.name, expensive.name)
    expect(response.body.index(cheap.name)).to be < response.body.index(expensive.name)
  end

  it "paginates at 24 products and safely bounds invalid page values" do
    25.times { |index| product(name: format("Paginated Match %02d", index), slug: "paginated-#{index}") }

    search "Paginated Match", page: "1"
    expect(response).to have_http_status(:ok)
    expect(document.css("a.home-card").length).to eq(24)

    search "Paginated Match", page: "2"
    expect(response).to have_http_status(:ok)
    expect(document.css("a.home-card").length).to eq(1)

    [ "0", "-20", "not-a-number", "999999999999999999999999" ].each do |page|
      search "Paginated Match", page: page
      expect(response).to have_http_status(:ok)
    end
  end

  it "does not expose search on disabled storefronts or the apex host" do
    store.update!(storefront_enabled: false)
    search "anything"
    expect(response).to have_http_status(:not_found)

    host! Store.base_domain
    get "/en/search", params: { q: "anything" }
    expect(response).to have_http_status(:not_found)
  end

  it "escapes a query before reflecting it into the result page" do
    payload = %(<script>alert("search-xss")</script>)

    search payload

    expect(response).to have_http_status(:ok)
    expect(document.css("script").map(&:text).join).not_to include("search-xss")
    expect(response.body).not_to include(payload)
    expect(document.at_css('input[type="search"]')["value"]).to eq(payload)
  end
end
