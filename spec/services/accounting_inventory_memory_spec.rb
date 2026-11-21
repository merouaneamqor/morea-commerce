# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountingStats, "inventory batching" do
  let(:store) { Store.create!(name: "Inventory", slug: "inventory-#{SecureRandom.hex(4)}", currency: "MAD") }

  def product(**attributes)
    store.products.create!({ name: "Synthetic product", slug: SecureRandom.hex(8), price_cents: 1000,
      cost_cents: 100, stock: 2, status: "active" }.merge(attributes))
  end

  it "totals all batches, including drafts and inactive variants, within the tenant" do
    stub_const("AccountingStats::INVENTORY_BATCH_SIZE", 2)
    product
    product(status: "draft", stock: 3, cost_cents: 200)
    variants = product(stock: 99, cost_cents: 300)
    variants.product_variants.create!(name: "Active", stock: 2, active: true)
    variants.product_variants.create!(name: "Inactive", stock: 3, active: false)
    product(stock: 0, cost_cents: nil)
    product(stock: 4, cost_cents: nil)
    foreign = Store.create!(name: "Other inventory", slug: "other-inventory-#{SecureRandom.hex(4)}", currency: "MAD")
    foreign.products.create!(name: "Foreign", slug: "foreign", price_cents: 1000, cost_cents: 999, stock: 999, status: "active")

    expect(described_class.new(store: store).inventory).to eq(cents: 2300, products: 5, out_of_stock: 1, missing_cost: 2)
  end

  it "loads bounded product batches without retaining their results in the request query cache" do
    stub_const("AccountingStats::INVENTORY_BATCH_SIZE", 2)
    5.times do
      product.product_variants.create!(name: "Synthetic variant", stock: 2, active: true)
    end
    product_batch_sizes = []
    cache_flags = []
    instantiated = lambda do |*args|
      payload = args.last
      product_batch_sizes << payload[:record_count] if payload[:class_name] == "Product"
    end
    queried = lambda do |*args|
      payload = args.last
      cache_flags << Product.connection.query_cache_enabled if payload[:sql].match?(/FROM "(?:products|product_variants)"/)
    end

    Product.cache do
      ActiveSupport::Notifications.subscribed(instantiated, "instantiation.active_record") do
        ActiveSupport::Notifications.subscribed(queried, "sql.active_record") do
          expect(described_class.new(store: store).inventory[:cents]).to eq(1000)
        end
      end
      expect(Product.connection.query_cache_enabled).to be_truthy
    end
    expect(product_batch_sizes).to eq([ 2, 2, 1 ])
    expect(cache_flags).not_to be_empty
    expect(cache_flags).to all(be_falsey)
  end

  it "returns zero counts for an empty catalog" do
    expect(described_class.new(store: store).inventory).to eq(cents: 0, products: 0, out_of_stock: 0, missing_cost: 0)
  end
end
