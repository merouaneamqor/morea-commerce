# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront Meta pixels", type: :request do
  let(:store) do
    Store.create!(
      slug: "pix-sf-#{SecureRandom.hex(4)}",
      name: "Pixel Storefront",
      currency: "MAD",
      storefront_enabled: true,
      meta_pixel_id: "123456789012345"
    )
  end
  let(:host) { "#{store.slug}.#{Store.base_domain}" }
  let!(:collection) { store.collections.create!(name: "Essentials", slug: "essentials", published: true) }
  let!(:product) do
    store.products.create!(
      name: "Basic Tracksuit",
      slug: "basic-tracksuit",
      sku: "BT-001",
      status: "active",
      price_cents: 49_900,
      stock: 5
    ).tap { |row| collection.products << row }
  end

  before { host! host }

  it "loads the Meta pixel and queues ViewContent with contents on the product page" do
    get "/en/products/#{product.slug}", headers: { "CF-IPCountry" => "MA" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("connect.facebook.net")
    expect(response.body).to include("_moreaMetaPixels")
    expect(response.body).to include('fbq(\'init\', id')
    expect(response.body).not_to include("ev=PageView&noscript=1")
    expect(response.body).to include('data-controller="pixels"')
    expect(response.body).to include('data-pixel-event-name-value="ViewContent"')
    expect(response.body).to include("BT-001")
    expect(response.body).to include("item_price")
  end

  it "fires ViewCategory on collections and Search on search results" do
    get "/en/collections/#{collection.slug}", headers: { "CF-IPCountry" => "MA" }
    expect(response.body).to include('data-pixel-event-name-value="ViewCategory"')
    expect(response.body).to include("Essentials")

    get "/en/search", params: { q: "tracksuit" }, headers: { "CF-IPCountry" => "MA" }
    expect(response.body).to include('data-pixel-event-name-value="Search"')
    expect(response.body).to include("tracksuit")
  end

  it "embeds advanced matching and a Purchase event after checkout" do
    post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }
    post "/en/checkout", params: {
      checkout: {
        name: "Amina Benali",
        phone: "0612345678",
        city: "Casablanca",
        address: "Street 1",
        privacy_accepted: "1",
        age_confirmed: "1"
      }
    }
    expect(response).to redirect_to(%r{/en/orders/})
    follow_redirect!

    expect(response.body).to include('data-pixel-event-name-value="Purchase"')
    expect(response.body).to include("purchase-")
    expect(response.body).to include("order_id")
    expect(response.body).to include("_moreaMetaPixels")
    expect(response.body).to match(/"ph":"\+212\d+"/)
    expect(response.body).to include('"fn":"amina"')
    expect(response.body).to include('"ct":"casablanca"')
    expect(response.body).not_to include("ev=PageView&noscript=1")
  end
end
