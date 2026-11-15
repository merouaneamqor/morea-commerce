# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Storefront collections", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:store) do
    Store.create!(
      slug: "coll-#{suffix}",
      name: "Synthetic collection store",
      currency: "MAD",
      storefront_enabled: true
    )
  end
  let(:collection) do
    store.collections.create!(name: "Essentials", slug: "essentials-#{suffix}", published: true)
  end

  def product(**attributes)
    row = store.products.create!({
      name: "Collection product #{SecureRandom.hex(4)}",
      slug: "collection-product-#{SecureRandom.hex(6)}",
      status: "active",
      price_cents: 10_000,
      stock: 5,
      track_inventory: true
    }.merge(attributes))
    collection.products << row
    row
  end

  def visit_collection(**params)
    host! "#{store.slug}.#{Store.base_domain}"
    get "/en/collections/#{collection.slug}", params: params
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "paginates at 24 products and keeps the total count accurate" do
    25.times { |index| product(name: format("Paged Collection %02d", index), slug: "paged-coll-#{index}") }

    visit_collection(page: 1)
    expect(response).to have_http_status(:ok)
    expect(document.css("a.home-card").length).to eq(24)
    expect(response.body).to include("Page 1 of 2")

    visit_collection(page: 2)
    expect(response).to have_http_status(:ok)
    expect(document.css("a.home-card").length).to eq(1)
  end

  it "filters sold-out rows in SQL before paginating" do
    product(name: "In Stock Coat", slug: "in-stock-coat", stock: 3)
    product(name: "Sold Out Coat", slug: "sold-out-coat", stock: 0)

    visit_collection(in_stock: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("In Stock Coat")
    expect(response.body).not_to include("Sold Out Coat")
  end
end
