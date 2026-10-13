# frozen_string_literal: true

# A-to-Z MCP smoke for product manager + inventory tracking.
# Usage: bin/rails runner script/mcp_inventory_smoke.rb [store_slug]
#
# Exercises MCP tools (and the GraphQL they wrap) including happy paths and edge cases.

require "json"
require "securerandom"

slug = ARGV[0].presence || ENV.fetch("DEFAULT_STORE_SLUG", "morea")
store = Store.find_by!(slug: slug)
ctx = { store: store }
prefix = "mcp-smoke-#{SecureRandom.hex(4)}"
passed = 0
failed = 0
failures = []

def mcp_json(response)
  part = Array(response.content).find { |row| (row[:type] || row["type"]) == "text" }
  raise "MCP response missing text content" unless part

  JSON.parse(part[:text] || part["text"])
end

def assert!(name, condition, detail = nil)
  if condition
    puts "  PASS  #{name}"
    true
  else
    message = detail.nil? ? name : "#{name}: #{detail}"
    puts "  FAIL  #{message}"
    raise message
  end
end

def expect_error!(name)
  begin
    yield
    assert!(name, false, "expected an error")
  rescue Inventory::Adjuster::Error, Catalog::Inventory::Error, Catalog::Changesets::Error, Catalog::Variants::Error, ArgumentError, StandardError => e
    raise if e.is_a?(SignalException)

    assert!(name, true, e.message)
    e
  end
end

section = lambda do |title|
  puts
  puts "== #{title} =="
end

run = lambda do |name, &block|
  block.call
  passed += 1
rescue StandardError => e
  failed += 1
  failures << "#{name}: #{e.message}"
  puts "  FAIL  #{name}: #{e.message}"
end

puts "Store: #{store.name} (#{store.slug})"
puts "Prefix: #{prefix}"
puts "MCP inventory tools registered: #{CatalogServer::TOOLS.count { |t| t.name.include?('Inventory') }}"

# ---------------------------------------------------------------------------
section.call("0. Tool registration")
run.call("inventory tools present") do
  names = CatalogServer::TOOLS.map { |t| t.name.demodulize.underscore }
  %w[list_inventory list_low_stock inventory_summary list_inventory_movements adjust_stock set_stock].each do |tool|
    assert!(tool, names.include?(tool))
  end
  schema = Catalog::Autonomy.product_schema
  assert!("schema inventoryTools", Array(schema["inventoryTools"]).include?("adjust_stock"))
  assert!("schema inventoryReasons", Array(schema["inventoryReasons"]).include?("received"))
end

# ---------------------------------------------------------------------------
section.call("1. Product manager — create / update / variants / images path via MCP")
simple_slug = "#{prefix}-simple"
variant_slug = "#{prefix}-variant"
inactive_slug = "#{prefix}-inactive"

run.call("create_product with initial stock") do
  resp = CatalogTools::CreateProduct.call(
    server_context: ctx,
    priceDh: 150,
    stock: 5,
    status: "active",
    slug: simple_slug,
    translations: [ { "locale" => "fr", "name" => "Smoke Simple", "shortDescription" => "linen" } ]
  )
  body = mcp_json(resp)
  assert!("create ok", !resp.error?, body)
  product = store.products.find_by!(slug: simple_slug)
  assert!("stock 5", product.stock == 5)
  assert!("ledger received", product.inventory_movements.where(reason: "received", quantity: 5).exists?)
end

run.call("update_product content + absolute stock via MCP") do
  resp = CatalogTools::UpdateProduct.call(
    server_context: ctx,
    slug: simple_slug,
    stock: 8,
    translations: [ { "locale" => "fr", "name" => "Smoke Simple", "shortDescription" => "updated" } ]
  )
  body = mcp_json(resp)
  assert!("update ok", !resp.error?, body)
  product = store.products.find_by!(slug: simple_slug)
  assert!("stock 8", product.stock == 8)
  assert!("correction movement", product.inventory_movements.where(reason: "correction").exists?)
end

run.call("create variant product + set_product_variants") do
  CatalogTools::CreateProduct.call(
    server_context: ctx,
    priceDh: 220,
    stock: 0,
    status: "active",
    slug: variant_slug,
    translations: [ { "locale" => "fr", "name" => "Smoke Variant" } ]
  )
  resp = CatalogTools::SetProductVariants.call(
    server_context: ctx,
    slug: variant_slug,
    variants: [
      { "size" => "M", "color" => "Noir", "stock" => 2 },
      { "size" => "L", "color" => "Noir", "stock" => 1 }
    ]
  )
  body = mcp_json(resp)
  assert!("variants ok", !resp.error?, body)
  product = store.products.find_by!(slug: variant_slug)
  assert!("two variants", product.product_variants.count == 2)
  assert!("initial variant ledger", product.inventory_movements.where(reason: "received").count >= 2)
end

# ---------------------------------------------------------------------------
section.call("2. Inventory MCP — happy path")
run.call("adjust_stock received") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: simple_slug, quantity: 4, reason: "received", note: "PO-1"
  )
  body = mcp_json(resp)
  assert!("adjust ok", !resp.error?, body)
  stock = body.dig("data", "adjustStock", "stock")
  assert!("stock 12", stock == 12, stock)
end

run.call("set_stock absolute") do
  resp = CatalogTools::Inventory::SetStock.call(
    server_context: ctx, slug: simple_slug, stock: 10, reason: "correction", note: "cycle count"
  )
  body = mcp_json(resp)
  assert!("set ok", !resp.error?, body)
  assert!("stock 10", body.dig("data", "setStock", "stock") == 10)
end

run.call("adjust_stock damaged") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: simple_slug, quantity: -2, reason: "damaged", note: "torn hem"
  )
  body = mcp_json(resp)
  assert!("damage ok", !resp.error?, body)
  assert!("stock 8", body.dig("data", "adjustStock", "stock") == 8)
end

run.call("list_inventory for product") do
  resp = CatalogTools::Inventory::ListInventory.call(server_context: ctx, slug: simple_slug)
  body = mcp_json(resp)
  rows = body.dig("data", "inventoryLevels")
  assert!("one row", rows.is_a?(Array) && rows.size == 1, rows)
  assert!("stock field", rows.first["stock"] == 8)
end

run.call("list_inventory for variants") do
  resp = CatalogTools::Inventory::ListInventory.call(server_context: ctx, slug: variant_slug)
  body = mcp_json(resp)
  rows = body.dig("data", "inventoryLevels")
  assert!("two variant rows", rows.size == 2, rows)
  assert!("has size", rows.all? { |row| row["size"].present? })
end

run.call("list_low_stock") do
  CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: 1)
  resp = CatalogTools::Inventory::ListLowStock.call(server_context: ctx, limit: 200)
  body = mcp_json(resp)
  rows = body.dig("data", "inventoryLevels")
  assert!("includes simple", rows.any? { |row| row["slug"] == simple_slug && row["lowStock"] == true }, rows)
end

run.call("inventory_summary") do
  resp = CatalogTools::Inventory::InventorySummary.call(server_context: ctx)
  body = mcp_json(resp)
  summary = body.dig("data", "inventorySummary")
  assert!("tracked", summary["trackedProducts"].to_i >= 1)
  assert!("byReason", summary["byReason"].is_a?(Array))
end

run.call("list_inventory_movements filters") do
  resp = CatalogTools::Inventory::ListInventoryMovements.call(
    server_context: ctx, slug: simple_slug, reason: "damaged", limit: 20
  )
  body = mcp_json(resp)
  rows = body.dig("data", "inventoryMovements")
  assert!("damaged rows", rows.any? { |row| row["reason"] == "damaged" && row["quantity"] == -2 }, rows)
end

run.call("variant adjust_stock by size+color") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: variant_slug, quantity: 5, reason: "received", size: "M", color: "Noir"
  )
  body = mcp_json(resp)
  assert!("variant adjust ok", !resp.error?, body)
  product = store.products.find_by!(slug: variant_slug)
  variant = product.product_variants.find { |v| v.size_value == "M" && v.color_value == "Noir" }
  assert!("M/Noir stock 7", variant.stock == 7, variant.stock)
end

run.call("variant set_stock by variantId") do
  product = store.products.find_by!(slug: variant_slug)
  variant = product.product_variants.find { |v| v.size_value == "L" && v.color_value == "Noir" }
  resp = CatalogTools::Inventory::SetStock.call(
    server_context: ctx, slug: variant_slug, stock: 9, variantId: variant.id.to_s, reason: "correction"
  )
  body = mcp_json(resp)
  assert!("variant set ok", !resp.error?, body)
  assert!("L/Noir stock 9", variant.reload.stock == 9)
end

run.call("export_csv inventory") do
  resp = CatalogTools::Storefront::ExportCsv.call(server_context: ctx, kind: "inventory")
  body = mcp_json(resp)
  csv = body.dig("data", "exportCsv", "csv").to_s
  assert!("csv header", csv.include?("slug,name,status"))
  assert!("csv product", csv.include?(simple_slug) || csv.include?(variant_slug), csv.lines.first(3))
end

# ---------------------------------------------------------------------------
section.call("3. Edge cases")
run.call("reject zero quantity") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: simple_slug, quantity: 0, reason: "manual_adjustment"
  )
  assert!("mcp error", resp.error?)
end

run.call("reject unknown reason") do
  begin
    resp = CatalogTools::Inventory::AdjustStock.call(
      server_context: ctx, slug: simple_slug, quantity: 1, reason: "theft"
    )
    assert!("mcp error", resp.error?)
  rescue ArgumentError, TypeError, MCP::Tool::ValidationError => e
    assert!("schema/validation rejected reason", true, e.message)
  end
end

run.call("reject negative absolute stock") do
  resp = CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: -1)
  assert!("mcp error", resp.error?)
end

run.call("reject stock below zero via adjust") do
  CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: 2)
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: simple_slug, quantity: -5, reason: "damaged"
  )
  assert!("mcp error", resp.error?)
  assert!("unchanged", store.products.find_by!(slug: simple_slug).stock == 2)
end

run.call("reject missing product") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: "#{prefix}-missing", quantity: 1, reason: "received"
  )
  assert!("mcp error", resp.error?)
end

run.call("reject product-level adjust when variants exist") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: variant_slug, quantity: 1, reason: "received"
  )
  assert!("mcp error", resp.error?)
  detail = mcp_json(resp).to_s
  assert!("mentions variants", detail.include?("variants") || detail.include?("variant"), detail)
end

run.call("reject update_product stock when variants exist") do
  resp = CatalogTools::UpdateProduct.call(server_context: ctx, slug: variant_slug, stock: 99)
  assert!("mcp error", resp.error?)
  product = store.products.find_by!(slug: variant_slug)
  assert!("product.stock untouched path", product.product_variants.sum(:stock) != 99)
end

run.call("reject unknown variant size/color") do
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: variant_slug, quantity: 1, reason: "received", size: "XXS", color: "Vert"
  )
  assert!("mcp error", resp.error?)
end

run.call("reject ambiguous variant when only size given and colors differ") do
  CatalogTools::SetProductVariants.call(
    server_context: ctx,
    slug: variant_slug,
    variants: [ { "size" => "M", "color" => "Blanc", "stock" => 1 } ]
  )
  resp = CatalogTools::Inventory::AdjustStock.call(
    server_context: ctx, slug: variant_slug, quantity: 1, reason: "received", size: "M"
  )
  assert!("mcp error", resp.error?)
end

run.call("set_stock no-op when unchanged writes no movement") do
  product = store.products.find_by!(slug: simple_slug)
  before = product.inventory_movements.count
  CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: product.stock)
  assert!("no new movement", product.inventory_movements.count == before)
end

run.call("inactive-only variants report zero sellable stock") do
  CatalogTools::CreateProduct.call(
    server_context: ctx,
    priceDh: 90,
    stock: 50,
    status: "active",
    slug: inactive_slug,
    translations: [ { "locale" => "fr", "name" => "Smoke Inactive" } ]
  )
  product = store.products.find_by!(slug: inactive_slug)
  Catalog::Variants.upsert!(product, [ { size: "S", color: "Rouge", stock: 3, active: false } ])
  product.update_columns(stock: 50)
  resp = CatalogTools::Inventory::ListInventory.call(server_context: ctx, slug: inactive_slug)
  body = mcp_json(resp)
  rows = body.dig("data", "inventoryLevels")
  assert!("one row", rows.size == 1, rows)
  assert!("sellable 0", rows.first["sellableStock"] == 0, rows)
  assert!("low stock", rows.first["lowStock"] == true)
end

run.call("untracked product levels") do
  product = store.products.find_by!(slug: simple_slug)
  product.update!(track_inventory: false)
  resp = CatalogTools::Inventory::ListInventory.call(server_context: ctx, slug: simple_slug)
  body = mcp_json(resp)
  row = body.dig("data", "inventoryLevels").first
  assert!("not tracking", row["trackInventory"] == false)
  assert!("nil stock", row["stock"].nil?)
  product.update!(track_inventory: true)
end

# ---------------------------------------------------------------------------
section.call("4. Changeset autonomy — create_product + adjust/set stock")
run.call("preview/apply/verify/rollback inventoty changeset") do
  cs_slug = "#{prefix}-cs"
  preview = Catalog::Changesets.preview(
    store,
    summary: "smoke inventory changeset",
    operations: [
      {
        "type" => "create_product",
        "slug" => cs_slug,
        "priceDh" => 70,
        "stock" => 3,
        "status" => "active",
        "translations" => [ { "locale" => "fr", "name" => "Smoke CS" } ]
      },
      {
        "type" => "adjust_stock",
        "slug" => simple_slug,
        "quantity" => 2,
        "reason" => "received",
        "note" => "changeset receive"
      },
      {
        "type" => "set_stock",
        "slug" => simple_slug,
        "stock" => 6,
        "reason" => "correction"
      }
    ]
  )
  assert!("maxLevel 2", preview[:max_level] == 2, preview[:max_level])

  expect_error!("level2 requires approval") do
    Catalog::Changesets.apply(store, token: preview[:token], approve_level2: false)
  end

  before_simple = store.products.find_by!(slug: simple_slug).stock
  applied = Catalog::Changesets.apply(store, token: preview[:token], approve_level2: true)
  assert!("applied", applied[:status] == "applied", applied[:status])
  created = store.products.find_by(slug: cs_slug)
  assert!("created", created.present?)
  assert!("created stock", created.stock == 3)
  assert!("set to 6", store.products.find_by!(slug: simple_slug).stock == 6)

  verified = Catalog::Changesets.verify(store, token: preview[:token])
  assert!("verified", verified[:verification]["ok"] == true, verified[:verification])

  rolled = Catalog::Changesets.rollback(store, token: preview[:token])
  assert!("rolled back", rolled[:status] == "rolled_back", rolled[:status])
  assert!("create removed", store.products.find_by(slug: cs_slug).nil?)
  # Rollback restores inventory snapshots in reverse (set_stock then adjust_stock).
  assert!("simple restored", store.products.find_by!(slug: simple_slug).stock == before_simple)
end

run.call("changeset rejects adjust_stock without variant targeting") do
  preview = Catalog::Changesets.preview(
    store,
    operations: [ { "type" => "adjust_stock", "slug" => variant_slug, "quantity" => 1, "reason" => "received" } ]
  )
  expect_error!("apply fails") do
    Catalog::Changesets.apply(store, token: preview[:token], approve_level2: true)
  end
end

# ---------------------------------------------------------------------------
section.call("5. Order lifecycle movements (reserve / restore)")
run.call("order confirm and cancel write ledger") do
  product = store.products.find_by!(slug: simple_slug)
  CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: 5)
  product.reload
  before = product.inventory_movements.count
  customer = store.customers.find_or_create_by!(phone: "0600000099") do |row|
    row.name = "Smoke Buyer"
    row.city = "Casablanca"
  end

  order = store.orders.create!(
    status: "new",
    customer: customer,
    customer_name: customer.name,
    customer_phone: customer.phone,
    customer_city: "Casablanca",
    customer_address: "1 Test St",
    subtotal_cents: product.price_cents * 2,
    shipping_cents: 0,
    discount_cents: 0,
    total_cents: product.price_cents * 2,
    currency: store.currency
  )
  order.order_items.create!(
    product: product,
    product_name: product.name,
    quantity: 2,
    unit_price_cents: product.price_cents,
    total_cents: product.price_cents * 2
  )

  order.transition_to!("confirmed")
  product.reload
  assert!("reserved stock 3", product.stock == 3, product.stock)
  assert!("order_confirmed movement", product.inventory_movements.where(reason: "order_confirmed", quantity: -2).exists?)

  order.transition_to!("cancelled")
  product.reload
  assert!("restored stock 5", product.stock == 5, product.stock)
  assert!("order_cancelled movement", product.inventory_movements.where(reason: "order_cancelled", quantity: 2).exists?)
  assert!("movements grew", product.inventory_movements.count >= before + 2)
end

run.call("insufficient stock on confirm") do
  product = store.products.find_by!(slug: simple_slug)
  CatalogTools::Inventory::SetStock.call(server_context: ctx, slug: simple_slug, stock: 1)
  customer = store.customers.find_or_create_by!(phone: "0600000098") do |row|
    row.name = "Smoke Buyer 2"
    row.city = "Rabat"
  end
  order = store.orders.create!(
    status: "new",
    customer: customer,
    customer_name: customer.name,
    customer_phone: customer.phone,
    customer_city: "Rabat",
    customer_address: "2 Test St",
    subtotal_cents: product.price_cents * 5,
    shipping_cents: 0,
    discount_cents: 0,
    total_cents: product.price_cents * 5,
    currency: store.currency
  )
  order.order_items.create!(
    product: product,
    product_name: product.name,
    quantity: 5,
    unit_price_cents: product.price_cents,
    total_cents: product.price_cents * 5
  )
  expect_error!("confirm fails") { order.transition_to!("confirmed") }
  assert!("stock still 1", product.reload.stock == 1)
end

# ---------------------------------------------------------------------------
section.call("Cleanup")
run.call("delete smoke products") do
  product_ids = store.products.where("slug LIKE ?", "#{prefix}%").pluck(:id)
  order_ids = OrderItem.where(product_id: product_ids).distinct.pluck(:order_id)
  InventoryMovement.where(product_id: product_ids).or(InventoryMovement.where(order_id: order_ids)).delete_all
  OrderItem.where(product_id: product_ids).delete_all
  OrderEvent.where(order_id: order_ids).delete_all if defined?(OrderEvent)
  Order.where(id: order_ids).delete_all
  ProductVariant.where(product_id: product_ids).delete_all
  ProductTranslation.where(product_id: product_ids).delete_all
  CollectionProduct.where(product_id: product_ids).delete_all
  store.products.where(id: product_ids).delete_all
  assert!("cleaned", store.products.where("slug LIKE ?", "#{prefix}%").none?)
end

puts
puts "Result: #{passed} passed, #{failed} failed"
failures.each { |row| puts "  - #{row}" }
raise "MCP inventory smoke failed" if failed.positive?

puts "OK"
