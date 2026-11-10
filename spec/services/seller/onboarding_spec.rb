# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seller::Onboarding do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) do
    Store.create!(
      name: "Onboard #{suffix}",
      slug: "onboard-#{suffix}",
      currency: "MAD",
      storefront_enabled: false
    )
  end

  def onboarding(workspace = store)
    described_class.new(store: workspace)
  end

  it "requires a persisted workspace" do
    expect { described_class.new(store: Store.new) }.to raise_error(ArgumentError)
  end

  it "lists connect, carrier and first-order steps for an external-only workspace" do
    steps = onboarding.steps
    expect(steps.map(&:key)).to eq(%w[source carrier first_order])
    expect(onboarding).to be_visible
    expect(onboarding).not_to be_complete
    expect(onboarding.done_count).to eq(0)
    expect(onboarding.total_count).to eq(3)
  end

  it "adds a products step when the Seallo storefront is enabled" do
    store.update!(storefront_enabled: true)
    expect(onboarding.steps.map(&:key)).to eq(%w[source products carrier first_order])
    expect(onboarding.steps.find { |step| step.key == "source" }.done).to eq(true)
    products = onboarding.steps.find { |step| step.key == "products" }
    expect(products.done).to eq(false)
    expect(products.path).to eq("/admin/products/new")
    expect(products.tour_target).to eq("products")
  end

  it "points the completed storefront step at Online Store so Themes is discoverable" do
    store.update!(storefront_enabled: true)
    store.products.create!(name: "Item", slug: "item-#{suffix}", status: "active", price_cents: 1000)
    products = onboarding.steps.find { |step| step.key == "products" }
    expect(products.done).to eq(true)
    expect(products.path).to eq("/admin/online_store")
    expect(products.tour_target).to eq("online_store")
  end

  it "marks source done after a store connection exists" do
    store.store_connections.create!(
      provider: "woocommerce",
      name: "Woo #{suffix}",
      external_domain: "woo-#{suffix}.example.test",
      token: "tok-#{SecureRandom.hex(12)}",
      webhook_secret: "synthetic-secret-#{SecureRandom.hex(8)}"
    )
    expect(onboarding.steps.find { |step| step.key == "source" }.done).to eq(true)
  end

  it "marks carrier done when an active delivery account exists" do
    store.delivery_accounts.create!(provider: "other", name: "Local courier", is_active: true)
    expect(onboarding.steps.find { |step| step.key == "carrier" }.done).to eq(true)
  end

  it "adds and completes the confirm step after order work advances past new" do
    customer = store.customers.create!(name: "Buyer", phone: "0612345678", email: "buyer-#{suffix}@example.test")
    order = store.orders.create!(
      customer: customer, number: "OB-#{suffix}", status: "new", currency: "MAD",
      customer_name: "Buyer", customer_phone: "0612345678", customer_city: "Casablanca",
      customer_address: "Rue 1", total_cents: 1200, subtotal_cents: 1200
    )
    expect(onboarding.steps.map(&:key)).to include("confirm")
    expect(onboarding.steps.find { |step| step.key == "confirm" }.done).to eq(false)

    order.update!(status: "confirmed")
    fresh = onboarding
    expect(fresh.steps.find { |step| step.key == "first_order" }.done).to eq(true)
    expect(fresh.steps.find { |step| step.key == "confirm" }.done).to eq(true)
  end

  it "hides the checklist only when every applicable step is done" do
    store.update!(storefront_enabled: true)
    store.products.create!(name: "Item", slug: "item-#{suffix}", status: "active", price_cents: 1000)
    store.store_connections.create!(
      provider: "youcan",
      name: "YouCan #{suffix}",
      external_domain: "youcan-#{suffix}.example.test",
      external_store_id: SecureRandom.uuid,
      token: "tok-#{SecureRandom.hex(12)}",
      webhook_secret: "synthetic-secret-#{SecureRandom.hex(8)}"
    )
    store.delivery_accounts.create!(provider: "other", name: "Courier", is_active: true)
    customer = store.customers.create!(name: "Buyer", phone: "0611111111", email: "done-#{suffix}@example.test")
    store.orders.create!(
      customer: customer, number: "DONE-#{suffix}", status: "confirmed", currency: "MAD",
      customer_name: "Buyer", customer_phone: "0611111111", customer_city: "Rabat",
      customer_address: "Rue 2", total_cents: 2000, subtotal_cents: 2000
    )

    result = onboarding
    expect(result).to be_complete
    expect(result).not_to be_visible
    expect(result.progress_percent).to eq(100)
  end
end
