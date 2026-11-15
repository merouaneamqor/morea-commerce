# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront funnel attribution", type: :request do
  let(:store) do
    Store.create!(
      slug: "funnel-sf-#{SecureRandom.hex(4)}",
      name: "Funnel Storefront",
      currency: "MAD",
      storefront_enabled: true
    )
  end
  let(:host) { "#{store.slug}.#{Store.base_domain}" }
  let!(:product) do
    store.products.create!(
      name: "Funnel Jacket",
      slug: "funnel-jacket",
      sku: "FJ-001",
      status: "active",
      price_cents: 29_900,
      stock: 8
    )
  end
  let(:ma_headers) { { "CF-IPCountry" => "MA" } }
  let(:fr_headers) { { "CF-IPCountry" => "FR" } }
  let(:query) do
    {
      utm_source: "facebook",
      utm_campaign: "120200000000001",
      utm_term: "120200000000002",
      utm_content: "120200000000003",
      fbclid: "Iw.AR.test"
    }
  end

  before { host! host }

  it "captures UTM attribution and funnel stages through checkout when measurement is allowed" do
    get "/en/products/#{product.slug}", params: query, headers: ma_headers
    expect(response).to have_http_status(:ok)

    visit = store.storefront_visits.sole
    expect(visit).to have_attributes(
      utm_source: "facebook",
      fbclid: "Iw.AR.test",
      meta_campaign_id: "120200000000001",
      meta_adset_id: "120200000000002",
      meta_ad_id: "120200000000003",
      funnel_stage: "product_viewed"
    )
    expect(visit.storefront_funnel_events.order(:id).pluck(:name)).to eq(%w[landed product_viewed])

    post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }, headers: ma_headers
    expect(visit.reload.funnel_stage).to eq("added_to_cart")

    get "/en/checkout", headers: ma_headers
    expect(visit.reload.funnel_stage).to eq("checkout_started")

    post "/en/checkout", params: {
      checkout: {
        name: "Sara Amrani",
        phone: "0611223344",
        city: "Rabat",
        address: "Avenue 2",
        privacy_accepted: "1",
        age_confirmed: "1"
      }
    }, headers: ma_headers
    expect(response).to redirect_to(%r{/en/orders/})

    order = store.orders.sole
    expect(order).to have_attributes(
      meta_campaign_id: "120200000000001",
      meta_adset_id: "120200000000002",
      meta_ad_id: "120200000000003"
    )
    expect(visit.reload).to have_attributes(funnel_stage: "ordered", order_id: order.id)
    expect(visit.storefront_funnel_events.order(:id).pluck(:name)).to eq(
      %w[landed product_viewed added_to_cart checkout_started ordered]
    )
  end

  it "keeps session attribution for the order when EU visitors have not consented, without writing visit rows" do
    get "/en/products/#{product.slug}", params: query, headers: fr_headers
    expect(store.storefront_visits).to be_empty

    post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }, headers: fr_headers
    post "/en/checkout", params: {
      checkout: {
        name: "Sara Amrani",
        phone: "0611223344",
        city: "Rabat",
        address: "Avenue 2",
        privacy_accepted: "1",
        age_confirmed: "1"
      }
    }, headers: fr_headers
    expect(response).to redirect_to(%r{/en/orders/})
    expect(store.orders.sole.meta_campaign_id).to eq("120200000000001")
    expect(store.storefront_visits).to be_empty
  end
end
