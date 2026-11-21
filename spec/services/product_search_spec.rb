# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::ProductSearch do
  let(:store) { Store.create!(name: "Search", slug: "search-#{SecureRandom.hex(4)}", currency: "MAD") }

  def product(name, **attrs)
    store.products.create!({ name: name, price_cents: 1000, status: "active", slug: SecureRandom.hex(8) }.merge(attrs))
  end

  def search(query)
    described_class.new(store: store, query: query).products
  end

  it "keeps accent folding, all-term matching and active variant matching across batches" do
    stub_const("Orders::ProductSearch::BATCH_SIZE", 2)
    3.times { |i| product("A nonmatch #{i}") }
    wanted = product("Z Trácksuit")
    wanted.product_variants.create!(name: "Blue", sku: "SPECIAL", stock: 1, active: true)
    inactive = product("Z Tracksuit inactive")
    inactive.product_variants.create!(name: "Blue", sku: "SPECIAL", stock: 1, active: false)

    expect(search("TRACK special").map(&:id)).to eq([ wanted.id ])
    expect(search("no-such-term")).to eq([])
  end

  it "returns the first 25 in name/id order and stops loading further batches" do
    stub_const("Orders::ProductSearch::BATCH_SIZE", 10)
    records = 40.times.map { |i| product(format("Match %02d", i)) }
    loaded = 0
    listener = ->(*args) { loaded += args.last[:record_count] if args.last[:class_name] == "Product" }
    results = nil
    ActiveSupport::Notifications.subscribed(listener, "instantiation.active_record") do
      results = search("match")
    end

    expect(results.map(&:id)).to eq(records.first(25).map(&:id))
    expect(loaded).to eq(30)
  end

  it "does not retain scanned query results in the request query cache" do
    stub_const("Orders::ProductSearch::BATCH_SIZE", 2)
    5.times { |i| product("Unmatched #{i}") }
    cached_flags = []
    listener = lambda do |*args|
      payload = args.last
      if payload[:sql].include?('FROM "products"')
        cached_flags << Product.connection.query_cache_enabled
      end
    end
    Product.cache do
      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { search("absent") }
      expect(Product.connection.query_cache_enabled).to be_truthy
    end
    expect(cached_flags).not_to be_empty
    expect(cached_flags).to all(be_falsey)
  end

  it "keeps the empty-query limit and excludes other tenants, drafts and disconnected products" do
    own = 12.times.map { |i| product(format("Visible %02d", i)) }
    product("Draft", status: "draft")
    connection = store.store_connections.create!(provider: "woocommerce", name: "Disabled", external_domain: "disabled.example.test", webhook_secret: "synthetic-secret-123456", active: false)
    product("Disconnected", store_connection: connection)
    foreign = Store.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}", currency: "MAD")
    foreign.products.create!(name: "Foreign", slug: "foreign", status: "active", price_cents: 1000)

    expect(search("").map(&:id)).to eq(own.first(10).map(&:id))
    expect(search("visible").map(&:id)).to eq(own.map(&:id))
    %w[draft disconnected foreign].each { |term| expect(search(term)).to eq([]) }
  end
end
