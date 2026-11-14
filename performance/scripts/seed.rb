# frozen_string_literal: true

raise "Use an isolated Rails test database" unless Rails.env.test?
raise "PERF_TARGET_TOKEN must be at least 24 characters" unless ENV.fetch("PERF_TARGET_TOKEN", "").size >= 24

slug = ENV.fetch("DEFAULT_STORE_SLUG", "morea")
raise "Use a fresh disposable database with no stores" if Store.exists?

Store.transaction do
  store = Store.create!(slug: slug, name: "Synthetic Performance Store", currency: "MAD", shipping_cents: 2000)
  product = store.products.create!(
    slug: "perf-product", name: "Performance Fixture Product", status: "active",
    price_cents: 10_000, track_inventory: true
  )
  product.product_variants.create!(name: "Performance Fixture Variant", active: true, stock: 1000, price_cents: 12_500)
  collection = store.collections.create!(slug: "perf-collection", name: "Performance Collection", published: true)
  collection.collection_products.create!(product: product)
end
puts "Synthetic storefront ready"
