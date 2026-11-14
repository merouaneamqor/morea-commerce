# frozen_string_literal: true

require "rails_helper"

RSpec.describe PixelsHelper, type: :helper do
  let(:store) { Store.create!(slug: "pix-help-#{SecureRandom.hex(4)}", name: "Pixel Helper", currency: "MAD", storefront_enabled: true, meta_pixel_id: "123456789012345") }
  let(:product) do
    store.products.create!(
      name: "Basic Tracksuit",
      slug: "basic-tracksuit",
      sku: "BT-001",
      status: "active",
      price_cents: 49_900,
      stock: 3
    )
  end

  before do
    without_partial_double_verification do
      allow(helper).to receive(:current_store).and_return(store)
      allow(helper).to receive(:measurement_allowed?).and_return(true)
    end
  end

  it "builds product payloads with stable content ids and Meta contents rows" do
    payload = helper.product_pixel_payload(product, quantity: 2)

    expect(payload).to include(
      content_ids: [ "BT-001" ],
      content_type: "product",
      content_name: "Basic Tracksuit",
      currency: "MAD",
      quantity: 2,
      num_items: 2,
      value: 998.0
    )
    expect(payload[:contents]).to eq([ { id: "BT-001", quantity: 2, item_price: 499.0 } ])
  end

  it "falls back to the product slug when sku is blank" do
    product.update!(sku: nil)
    expect(helper.product_pixel_payload(product)[:content_ids]).to eq([ "basic-tracksuit" ])
  end

  it "builds purchase payloads with order_id and event_id for deduplication" do
    customer = store.customers.create!(name: "Amina Benali", phone: "0612345678", city: "Casablanca")
    order = store.orders.create!(
      number: "PIX-1001",
      status: "new",
      customer: customer,
      customer_name: "Amina Benali",
      customer_phone: "0612345678",
      customer_city: "Casablanca",
      customer_district: "Maarif",
      customer_address: "Street 1",
      currency: "MAD",
      subtotal_cents: 49_900,
      shipping_cents: 0,
      discount_cents: 0,
      total_cents: 49_900
    )
    order.order_items.create!(
      product: product,
      product_name: product.name,
      quantity: 1,
      unit_price_cents: 49_900,
      total_cents: 49_900
    )

    payload = helper.order_pixel_payload(order)
    expect(payload).to include(
      order_id: "PIX-1001",
      event_id: "purchase-PIX-1001",
      value: 499.0,
      currency: "MAD",
      content_ids: [ "BT-001" ]
    )
    expect(helper.order_pixel_user_data(order)).to include(
      ph: "0612345678",
      fn: "amina",
      ln: "benali",
      ct: "casablanca",
      st: "maarif",
      country: "ma",
      external_id: "PIX-1001"
    )
  end

  it "renders pixel event tags with JSON object payloads for Stimulus" do
    html = helper.pixel_event_tag("ViewContent", helper.product_pixel_payload(product))
    expect(html).to include('data-controller="pixel-event"')
    expect(html).to include('data-pixel-event-name-value="ViewContent"')
    expect(html).to include("BT-001")
    expect(html).not_to include("&quot;{&quot;")
  end
end
