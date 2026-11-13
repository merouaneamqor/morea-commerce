# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Sitemaps", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let!(:store) do
    Store.create!(
      slug: "sitemap-#{suffix}",
      name: "Synthetic sitemap store",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  def sitemap_locations
    document = Nokogiri::XML(response.body)
    document.remove_namespaces!
    document.xpath("//url/loc").map(&:text)
  end

  def tenant_host(workspace = store)
    "#{workspace.slug}.#{Store.base_domain}"
  end

  it "serves a root-only XML sitemap on the apex domain" do
    host! Store.base_domain

    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(sitemap_locations).to eq([ "http://#{Store.base_domain}/" ])
  end

  it "serves localized public URLs for an enabled tenant" do
    active_product = store.products.create!(
      name: "Published product",
      slug: "published-product",
      status: "active",
      price_cents: 10_000,
      stock: 4
    )
    published_collection = store.collections.create!(name: "Published collection", slug: "published-collection")
    content_page = store.pages.create!(slug: "shipping", template: "content", published: true)
    landing_page = store.pages.create!(slug: "campaign", template: "landing", published: true)

    host! tenant_host
    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")

    locations = sitemap_locations
    %w[fr en ar].each do |locale|
      expect(locations).to include(
        "http://#{tenant_host}/#{locale}",
        "http://#{tenant_host}/#{locale}/products/#{active_product.slug}",
        "http://#{tenant_host}/#{locale}/collections/#{published_collection.slug}",
        "http://#{tenant_host}/#{locale}/pages/#{content_page.slug}",
        "http://#{tenant_host}/#{locale}/pages/#{landing_page.slug}"
      )
    end
  end

  it "excludes unpublished, inactive, and foreign-tenant content" do
    own_active = store.products.create!(name: "Own active", slug: "own-active", status: "active", price_cents: 5_000)
    store.products.create!(name: "Own draft", slug: "own-draft", status: "draft", price_cents: 5_000)
    store.products.create!(name: "Own archived", slug: "own-archived", status: "archived", price_cents: 5_000)
    store.collections.create!(name: "Hidden collection", slug: "hidden-collection", published: false)
    store.pages.create!(slug: "hidden-page", published: false)

    foreign_store = Store.create!(
      slug: "foreign-sitemap-#{suffix}",
      name: "Foreign synthetic sitemap store",
      currency: "MAD",
      storefront_enabled: true
    )
    foreign_store.products.create!(name: "Foreign active", slug: "foreign-active", status: "active", price_cents: 8_000)
    foreign_store.collections.create!(name: "Foreign collection", slug: "foreign-collection", published: true)
    foreign_store.pages.create!(slug: "foreign-page", published: true)

    host! tenant_host
    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    locations = sitemap_locations
    expect(locations).to include("http://#{tenant_host}/fr/products/#{own_active.slug}")
    expect(locations.join("\n")).not_to include(
      "own-draft",
      "own-archived",
      "hidden-collection",
      "hidden-page",
      "foreign-active",
      "foreign-collection",
      "foreign-page",
      foreign_store.slug
    )
  end

  it "does not expose a sitemap for a disabled tenant" do
    store.update!(storefront_enabled: false)
    host! tenant_host

    get "/sitemap.xml"

    expect(response).to have_http_status(:not_found)
  end

  it "returns not found for an unknown tenant host" do
    host! "unknown-#{suffix}.#{Store.base_domain}"

    get "/sitemap.xml"

    expect(response).to have_http_status(:not_found)
  end
end
