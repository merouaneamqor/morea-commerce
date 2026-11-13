# frozen_string_literal: true

raise "Intake smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
suffix = SecureRandom.hex(5)
store = Store.create!(slug: "intake-#{suffix}", name: "Intake CI", currency: "MAD")
other = Store.create!(slug: "intake-other-#{suffix}", name: "Other intake CI", currency: "MAD")
product = store.products.create!(slug: "intake-product", name: "Intake Product", price_cents: 12_500, stock: 20, status: "active", track_inventory: true)
foreign = other.products.create!(slug: "intake-product", name: "Other Intake Product", price_cents: 30_000, stock: 5, status: "active", track_inventory: true)
attrs = { name: "Synthetic Buyer", phone: "0612345678", city: "Casablanca", address: "Synthetic address",
  lines: [ { product_id: product.id, quantity: 2 } ], shipping_dh: "20.00" }
intake = Orders::Intake.new(store: store)
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }
reject = lambda do |message, &block|
  rejected = false
  begin
    block.call
  rescue Orders::Intake::Error
    rejected = true
  end
  assert.call(message, rejected)
end
jobs_before = ActiveJob::Base.queue_adapter.enqueued_jobs.length
result = intake.call(source: "SHOPIFY", external_id: "order-77", attrs: attrs)
assert.call("created result", result.created? && !result.replayed?)
assert.call("catalog price + explicit shipping", result.order.total_cents == 27_000)
assert.call("incoming order stays new", result.order.status == "new")
assert.call("intake does not reserve stock", product.reload.stock == 20 && !result.order.inventory_movements.exists?)
assert.call("intake does not enqueue external notifications", ActiveJob::Base.queue_adapter.enqueued_jobs.length == jobs_before)
replay = intake.call(source: "shopify", external_id: "order-77", attrs: attrs.merge(name: "Changed", lines: []))
assert.call("replay returns original, not changed payload", replay.replayed? && replay.order.id == result.order.id && replay.order.customer_name == "Synthetic Buyer")
assert.call("one identity and order", OrderImport.where(store: store).count == 1 && store.orders.count == 1)
assert.call("source stored normalized", OrderImport.find_by!(order: result.order).source == "shopify")
assert.call("import provenance event", result.order.order_events.where(kind: "comment", body: "Imported from shopify").exists?)
reject.call("cross-store product rejected") { intake.call(source: "shopify", external_id: "foreign", attrs: attrs.merge(lines: [ { product_id: foreign.id, quantity: 1 } ])) }
reject.call("fractional quantities rejected") { intake.call(source: "shopify", external_id: "fractional", attrs: attrs.merge(lines: [ { product_id: product.id, quantity: 1.5 } ])) }
reject.call("negative shipping rejected") { intake.call(source: "shopify", external_id: "negative", attrs: attrs.merge(shipping_dh: -1)) }
reject.call("overflowing shipping rejected before float conversion") { intake.call(source: "shopify", external_id: "shipping-overflow", attrs: attrs.merge(shipping_dh: "9" * 400)) }
reject.call("overflowing discount rejected before float conversion") { intake.call(source: "shopify", external_id: "discount-overflow", attrs: attrs.merge(discount_dh: "9" * 400)) }
reject.call("shipping above SQL cents range rejected") { intake.call(source: "shopify", external_id: "shipping-range", attrs: attrs.merge(shipping_dh: "21474836.48")) }
reject.call("discount above SQL cents range rejected") { intake.call(source: "shopify", external_id: "discount-range", attrs: attrs.merge(discount_dh: "21474836.48")) }
reject.call("unknown scope fields rejected") { intake.call(source: "shopify", external_id: "scope", attrs: attrs.merge(store_id: other.id)) }
reject.call("unknown line fields rejected") { intake.call(source: "shopify", external_id: "price", attrs: attrs.merge(lines: [ { product_id: product.id, quantity: 1, unit_price_cents: 1 } ])) }
reject.call("invalid source rejected") { intake.call(source: "../shopify", external_id: "bad", attrs: attrs) }
reject.call("blank external ID rejected") { intake.call(source: "shopify", external_id: " ", attrs: attrs) }
reject.call("invalid contact rejected") { intake.call(source: "shopify", external_id: "contact", attrs: attrs.merge(phone: "invalid")) }
reject.call("structured country rejected") { intake.call(source: "shopify", external_id: "country-shape", attrs: attrs.merge(phone_country: { country: "MA" })) }
reject.call("structured name rejected") { intake.call(source: "shopify", external_id: "name-shape", attrs: attrs.merge(name: [ "name" ])) }
reject.call("nested tags rejected") { intake.call(source: "shopify", external_id: "tags-shape", attrs: attrs.merge(tags: [ { value: "VIP" } ])) }
assert.call("invalid requests leave no records", store.orders.count == 1 && OrderImport.where(store: store).count == 1)
second = Orders::Intake.new(store: other).call(source: "shopify", external_id: "order-77", attrs: attrs.merge(lines: [ { product_id: foreign.id, quantity: 1 } ]))
assert.call("external identities scoped by tenant", second.created? && second.order.store_id == other.id && second.order.id != result.order.id)
assert.call("source scoped independently", intake.call(source: "sheets", external_id: "order-77", attrs: attrs).created?)
rollback_count = store.orders.count
rollback_customers = store.customers.count
ActiveRecord::Base.transaction do
  intake.call(source: "rollback", external_id: "rolled-back", attrs: attrs.merge(phone: "0612345679"))
  raise ActiveRecord::Rollback
end
assert.call("outer rollback removes identity and full order", !OrderImport.where(store: store, source: "rollback").exists? && store.orders.count == rollback_count)
assert.call("outer rollback removes customer", store.customers.count == rollback_customers)
assert.call("rollback never enqueues notification", ActiveJob::Base.queue_adapter.enqueued_jobs.length == jobs_before)
# Real connections contend for the tenant lock; both callers must receive one order.
ready = Queue.new
release = Queue.new
threads = 2.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      ready << true
      release.pop
      Orders::Intake.new(store: Store.find(store.id)).call(source: "concurrent", external_id: "same", attrs: attrs)
    end
  end
end
2.times { ready.pop }
2.times { release << true }
concurrent = threads.map(&:value)
assert.call("concurrent replay creates exactly once", concurrent.count(&:created?) == 1 && concurrent.map { |entry| entry.order.id }.uniq.one?)
assert.call("one concurrent database identity", OrderImport.where(store: store, source: "concurrent", external_id: "same").count == 1)
assert.call("concurrent intake leaves stock untouched", product.reload.stock == 20)
variant = product.product_variants.create!(name: "M", option1_value: "M", stock: 5, active: true)
reject.call("variant products require selection") { intake.call(source: "shopify", external_id: "variant-missing", attrs: attrs) }
variant_result = intake.call(source: "shopify", external_id: "variant", attrs: attrs.merge(lines: [ { product_id: product.id, product_variant_id: variant.id, quantity: 1 } ]))
assert.call("selected variant is retained", variant_result.order.order_items.first.product_variant_id == variant.id)
puts "Order intake: #{checks} checks passed"
