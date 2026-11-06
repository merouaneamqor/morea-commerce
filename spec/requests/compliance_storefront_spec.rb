# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Compliance storefront", type: :request do
  let(:store) do
    Store.create!(
      slug: "comp-#{SecureRandom.hex(4)}",
      name: "Compliance Store",
      currency: "MAD",
      storefront_enabled: true,
      meta_pixel_id: "123456789012345",
      legal_entity_name: "Compliance SARL",
      legal_registration_number: "ICE-123",
      legal_address: "1 Rue Test, Casablanca",
      minimum_purchase_age: 16
    )
  end
  let(:host) { "#{store.slug}.lvh.me" }

  before do
    host! host
    OnlineStoreDefaults.new(store).install!
    DataProtection::Bootstrap.install_for_store!(store)
  end

  it "installs privacy, terms and cookies pages" do
    expect(store.pages.published.pluck(:slug)).to include("privacy", "terms", "cookies", "returns")
  end

  it "shows the cookie banner until a choice is recorded and gates pixels" do
    get "/en"
    expect(response.body).to include("cookie-consent")
    expect(response.body).not_to include("connect.facebook.net")

    post tracking_consent_path, params: { choice: "denied" }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(cookies["morea_tracking_consent"]).to eq("denied")

    get "/en"
    expect(response.body).not_to include("cookie-consent")
    expect(response.body).not_to include("connect.facebook.net")

    post tracking_consent_path, params: { choice: "granted" }, as: :json
    get "/en"
    expect(response.body).to include("connect.facebook.net")
  end

  it "shows imprint and age note in the footer" do
    get "/en"
    expect(response.body).to include("Compliance SARL")
    expect(response.body).to include("ICE-123")
    expect(response.body).to include("1 Rue Test, Casablanca")
    expect(response.body).to include("aged 16")
  end

  it "records a buyer data-rights request" do
    get "/en/privacy_rights"
    expect(response).to have_http_status(:ok)

    expect {
      post "/en/privacy_rights", params: {
        privacy_rights_request: {
          request_type: "delete",
          requester_name: "Buyer",
          requester_contact: "buyer@example.test",
          details: "Please erase my order history"
        }
      }
    }.to change { store.privacy_rights_requests.count }.by(1)

    expect(response).to redirect_to("/en/privacy_rights")
    expect(store.privacy_rights_requests.last).to have_attributes(request_type: "delete", status: "open")
  end

  it "requires checkout consents before placing an order" do
    product = store.products.create!(name: "Item", slug: "item", status: "active", price_cents: 1000, stock: 5)
    post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }

    post "/en/checkout", params: {
      checkout: {
        name: "Buyer", phone: "0612345678", city: "Casablanca", address: "Street 1"
      }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(store.orders.count).to eq(0)

    post "/en/checkout", params: {
      checkout: {
        name: "Buyer", phone: "0612345678", city: "Casablanca", address: "Street 1",
        privacy_accepted: "1", age_confirmed: "1"
      }
    }
    expect(response).to redirect_to(%r{/en/orders/})
    expect(store.orders.count).to eq(1)
  end
end
