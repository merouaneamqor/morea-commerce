# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::Intake do
  include ActiveJob::TestHelper

  let(:store) { Store.create!(slug: "intake-#{SecureRandom.hex(4)}", name: "Intake", currency: "MAD") }
  let(:other) { Store.create!(slug: "intake-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD") }
  let!(:product) do
    store.products.create!(slug: "intake-product", name: "Intake Product", price_cents: 12_500,
      stock: 20, status: "active", track_inventory: true)
  end
  let!(:foreign) do
    other.products.create!(slug: "intake-product", name: "Other Product", price_cents: 30_000,
      stock: 5, status: "active", track_inventory: true)
  end
  let(:attrs) do
    {
      name: "Synthetic Buyer",
      phone: "0612345678",
      city: "Casablanca",
      address: "Synthetic address",
      lines: [ { product_id: product.id, quantity: 2 } ],
      shipping_dh: "20.00"
    }
  end
  let(:intake) { described_class.new(store: store) }

  it "creates a new COD intake order without reserving stock or enqueueing alerts" do
    jobs_before = enqueued_jobs.size
    result = intake.call(source: "SHOPIFY", external_id: "order-77", attrs: attrs)

    expect(result).to be_created
    expect(result.order).to have_attributes(status: "new", total_cents: 27_000)
    expect(product.reload.stock).to eq(20)
    expect(result.order.inventory_movements).to be_empty
    expect(enqueued_jobs.size).to eq(jobs_before)
    expect(OrderImport.find_by!(order: result.order).source).to eq("shopify")
  end

  it "replays the original order for the same source and external id" do
    first = intake.call(source: "shopify", external_id: "order-77", attrs: attrs)
    replay = intake.call(source: "shopify", external_id: "order-77",
      attrs: attrs.merge(name: "Changed", lines: []))

    expect(replay).to be_replayed
    expect(replay.order.id).to eq(first.order.id)
    expect(replay.order.customer_name).to eq("Synthetic Buyer")
    expect(OrderImport.where(store: store).count).to eq(1)
    expect(store.orders.count).to eq(1)
  end

  it "rejects cross-store products and price injection on lines" do
    expect {
      intake.call(source: "shopify", external_id: "foreign",
        attrs: attrs.merge(lines: [ { product_id: foreign.id, quantity: 1 } ]))
    }.to raise_error(Orders::Intake::Error)

    expect {
      intake.call(source: "shopify", external_id: "price",
        attrs: attrs.merge(lines: [ { product_id: product.id, quantity: 1, unit_price_cents: 1 } ]))
    }.to raise_error(Orders::Intake::Error)

    expect(store.orders.count).to eq(0)
  end

  it "scopes external identities by tenant" do
    first = intake.call(source: "shopify", external_id: "order-77", attrs: attrs)
    second = described_class.new(store: other).call(
      source: "shopify",
      external_id: "order-77",
      attrs: attrs.merge(lines: [ { product_id: foreign.id, quantity: 1 } ])
    )

    expect(second).to be_created
    expect(second.order.store_id).to eq(other.id)
    expect(second.order.id).not_to eq(first.order.id)
  end
end
