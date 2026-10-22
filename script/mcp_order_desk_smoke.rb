# frozen_string_literal: true

raise "Order desk smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test

suffix = SecureRandom.hex(4)
store = Store.create!(slug: "desk-#{suffix}", name: "Order desk CI", currency: "MAD")
other = Store.create!(slug: "other-desk-#{suffix}", name: "Other CI", currency: "MAD")
product = store.products.create!(slug: "desk-product", name: "Desk Product", price_cents: 10_000, stock: 10, status: "active", track_inventory: true)
foreign_product = other.products.create!(slug: "foreign-product", name: "Other Product", price_cents: 20_000, stock: 10, status: "active")
attrs = { "name" => "CI Buyer", "phone" => "0612345678", "city" => "Casablanca", "address" => "CI test address",
  "lines" => [ { "productSlug" => product.slug, "quantity" => 2 } ], "shippingDh" => 20 }
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }
reject = lambda do |message, &block|
  rejected = false
  begin
    block.call
  rescue Catalog::OrderDesk::Error
    rejected = true
  end
  assert.call(message, rejected)
end
run = lambda do |action, number = nil, fields = {}, confirm = true|
  Catalog::OrderDesk.perform(store, action: action, number: number, attrs: fields, confirm: confirm)
end
reject.call("creation needs confirmation") { run.call("create", nil, attrs, false) }
assert.call("no unconfirmed order", store.orders.count.zero?)
reject.call("cross-store product rejected") { run.call("create", nil, attrs.merge("lines" => [ { "productSlug" => foreign_product.slug, "quantity" => 1 } ])) }
reject.call("fractional quantity rejected") { run.call("create", nil, attrs.merge("lines" => [ { "productSlug" => product.slug, "quantity" => 1.5 } ])) }
created = run.call("create", nil, attrs)
number = created.fetch("number")
order = store.orders.find_by!(number: number)
assert.call("catalog pricing", created["totalDh"] == 220)
assert.call("default result excludes contact", !created.key?("shipTo"))
run.call("transition", number, { "status" => "confirmed" })
assert.call("confirmation reserves stock", product.reload.stock == 8)
run.call("update", number, { "lines" => [ { "productSlug" => product.slug, "quantity" => 3 } ] })
assert.call("edit adjusts inventory", product.reload.stock == 7)
assert.call("partial edit keeps shipping", order.reload.shipping_cents == 2000)
assert.call("partial edit keeps contact", order.customer_address == "CI test address")
reject.call("unknown attrs rejected") { run.call("update", number, { "store_id" => other.id }) }
reject.call("invalid transition rejected") { run.call("transition", number, { "status" => "delivered" }) }
reject.call("cancellation cannot bypass dedicated tool") { run.call("transition", number, { "status" => "cancelled" }) }
run.call("tags", number, { "tags" => [ "VIP", "vip", "Priority" ] })
assert.call("tags normalized", order.reload.tag_list == %w[vip priority])
run.call("comment", number, { "body" => "CI internal note" })
assert.call("comment recorded", order.order_events.where(kind: "comment", body: "CI internal note").exists?)
run.call("archive", number)
assert.call("archived", order.reload.archived?)
run.call("unarchive", number)
assert.call("unarchived", !order.reload.archived?)
details = Catalog::OrderDesk.details(store, number: number)
assert.call("activity excludes contact", !details.key?("shipTo"))
assert.call("activity includes events", details["events"].any?)
slip = Catalog::OrderDesk.details(store, number: number, include_contact: true)
assert.call("explicit contact available", slip.dig("shipTo", "address") == "CI test address")
reject.call("cross-store order rejected") { Catalog::OrderDesk.details(other, number: number) }
reject.call("missing Sendit configuration rejected") { run.call("shipment", number, { "operation" => "push" }) }
copy = run.call("duplicate", number)
assert.call("duplicate gets new number", copy["number"] != number && copy["status"] == "new")
assert.call("duplicate doesn't reserve inventory", product.reload.stock == 7)

response = CatalogTools::OrderDesk::UpdateOrderTags.call(server_context: { store: store }, number: number, tags: [ "mcp" ], confirm: true)
assert.call("MCP wrapper executes GraphQL", !response.error? && order.reload.tag_list == [ "mcp" ])
response = CatalogTools::OrderDesk::GetPackingSlip.call(server_context: { store: other }, number: number)
assert.call("MCP wrapper enforces tenant isolation", response.error?)
CatalogTools::CancelOrder.call(server_context: { store: store }, number: number, confirm: true)
assert.call("cancellation restores edited quantity", product.reload.stock == 10)
reject.call("cancelled order locked") { run.call("update", number, { "notes" => "Cannot edit" }) }
assert.call("all new tools registered", [ CatalogTools::OrderDesk::CreateOrder, CatalogTools::OrderDesk::GetPackingSlip ].all? { |tool| CatalogServer::TOOLS.include?(tool) })
puts "Order desk: #{checks} checks passed"
