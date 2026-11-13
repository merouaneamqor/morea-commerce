# frozen_string_literal: true

raise "Connected store smoke requires isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
suffix = SecureRandom.hex(5)
store = Store.create!(slug: "connected-#{suffix}", name: "Synthetic connected store", currency: "MAD")
other = Store.create!(slug: "connected-other-#{suffix}", name: "Synthetic other store", currency: "MAD")
secret = "synthetic-webhook-secret-#{suffix}"
checks = 0
assert = ->(message, condition) { raise message unless condition; checks += 1 }
connection = store.store_connections.create!(provider: "shopify", name: "Synthetic Shopify", external_domain: "synthetic-#{suffix}.myshopify.com", webhook_secret: secret)
assert.call("secret encrypted at rest", !connection.webhook_secret_ciphertext.include?(secret) && connection.reload.webhook_secret == secret)
assert.call("not verified on configuration", connection.connection_state == "configured")
address = { "name" => "Synthetic buyer", "first_name" => "Synthetic", "last_name" => "Buyer", "phone" => "0612345678", "city" => "Casablanca", "address1" => "Synthetic address", "country_code" => "MA" }
shopify = { "id" => 123, "currency" => "MAD", "financial_status" => "pending", "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "total_tax" => "0.00", "total_discounts" => "0.00", "total_price" => "269.90", "shipping_address" => address,
  "total_shipping_price_set" => { "shop_money" => { "amount" => "20.00", "currency_code" => "MAD" } },
  "line_items" => [ { "name" => "External product", "quantity" => 2, "price" => "124.95" } ] }
headers = { "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain }
deliver = lambda do |conn, payload, hdrs|
  body = JSON.generate(payload)
  digest = OpenSSL::HMAC.digest("sha256", secret, body)
  signature_header = { "shopify" => "X-Shopify-Hmac-SHA256", "woocommerce" => "X-WC-Webhook-Signature", "youcan" => "X-YOUCAN-SIGNATURE" }.fetch(conn.provider)
  signature = conn.provider == "youcan" ? digest.unpack1("H*") : Base64.strict_encode64(digest)
  Connections::WebhookIntake.new(connection: conn).call(body: body, headers: hdrs.merge(signature_header => signature))
end
jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
result = deliver.call(connection, shopify, headers)
order = result.receipt.order
assert.call("external lines retain exact cents", order.total_cents == 26_990 && order.order_items.first.unit_price_cents == 12_495)
assert.call("no local product required", order.order_items.first.product.nil? && store.products.empty?)
assert.call("new COD enters existing queue", order.status == "new" && order.payment_method == "cod")
assert.call("no jobs or stock movement", ActiveJob::Base.queue_adapter.enqueued_jobs.size == jobs && order.inventory_movements.empty?)
assert.call("source verified", connection.reload.connection_state == "verified")
replay = deliver.call(connection, shopify.merge("total_price" => "999.00"), headers)
assert.call("replay does not mutate order", replay.replayed && replay.receipt.order_id == order.id && order.reload.total_cents == 26_990 && store.orders.count == 1)
rejected = deliver.call(connection, shopify.merge("id" => 124, "total_tax" => "1.00"), headers)
assert.call("unsupported money visible safely", rejected.receipt.error_code == "unsupported_tax_or_discount" && rejected.receipt.order.nil? && connection.reload.last_error_code == "unsupported_tax_or_discount")
assert.call("rejections create no customer/order", store.orders.count == 1 && store.customers.count == 1)
retry_result = deliver.call(connection, shopify.merge("id" => 124), headers)
assert.call("corrected rejected delivery can retry", retry_result.receipt.status == "accepted" && store.orders.count == 2)
begin
  deliver.call(connection, shopify.merge("id" => 125), headers.merge("X-Shopify-Shop-Domain" => "foreign.myshopify.com"))
  raise "foreign source accepted"
rescue Connections::WebhookIntake::Error => error
  assert.call("source mismatch denied", error.message == "source_mismatch")
end
begin
  Connections::WebhookIntake.new(connection: connection).call(body: JSON.generate(shopify), headers: headers)
  raise "missing signature accepted"
rescue Connections::WebhookIntake::Error => error
  assert.call("missing signature denied", error.status == 401)
end
foreign = other.store_connections.create!(provider: "shopify", name: "Other source", external_domain: connection.external_domain, webhook_secret: secret)
other_result = deliver.call(foreign, shopify, headers)
assert.call("identity isolated by tenant", other_result.receipt.order.store_id == other.id)
connection.update!(active: false)
begin
  deliver.call(connection, shopify, headers)
  raise "disconnected accepted"
rescue Connections::WebhookIntake::Error => error
  assert.call("disconnect denies deliveries", error.status == 410)
end
connection.update!(active: true)
order.transition_to!("confirmed", sync_delivery: false)
order.transition_to!("cancelled", sync_delivery: false)
assert.call("external snapshot lifecycle tolerates no product", order.status == "cancelled" && order.inventory_movements.empty?)

woo = store.store_connections.create!(provider: "woocommerce", name: "Woo source", external_domain: "synthetic.example", webhook_secret: secret)
woo_order = { "id" => 123, "currency" => "MAD", "payment_method" => "cod", "status" => "processing", "total_tax" => "0.00", "discount_total" => "0.00", "total" => "269.90", "shipping_total" => "20.00",
  "billing" => { "phone" => "0612345678" }, "shipping" => { "first_name" => "Synthetic", "last_name" => "Buyer", "city" => "Casablanca", "address_1" => "Synthetic street", "country" => "MA" },
  "line_items" => [ { "name" => "Woo external", "quantity" => 2, "total" => "249.90", "subtotal" => "249.90", "variation_id" => 42,
    "meta_data" => [ { "key" => "pa_size", "display_key" => "Size", "display_value" => "<p>XL</p>" }, { "key" => "_private_note", "display_key" => "Note", "display_value" => "do not copy this" } ] } ] }
woo_headers = { "X-WC-Webhook-Topic" => "order.created", "X-WC-Webhook-Source" => "https://synthetic.example/" }
woo_received = deliver.call(woo, woo_order, woo_headers).receipt.order
assert.call("Woo signed intake", woo_received.total_cents == 26_990)
assert.call("Woo selected variant survives without private metadata", woo_received.order_items.first.variant_name == "Size: XL")
woo_fallback = woo_order.deep_dup
woo_fallback["id"] = 456
woo_fallback["line_items"].first["meta_data"] = []
assert.call("Woo missing options preserve variation identity", deliver.call(woo, woo_fallback, woo_headers).receipt.order.order_items.first.variant_name == "Variation #42")

youcan = store.store_connections.create!(provider: "youcan", name: "YouCan source", external_domain: "synthetic.youcan.shop", external_store_id: SecureRandom.uuid, webhook_secret: secret)
youcan_order = { "event_name" => "order.created", "data" => { "id" => SecureRandom.uuid, "store_id" => youcan.external_store_id, "currency" => "MAD", "total" => 269.9, "vat" => 0,
  "status_object" => { "slug" => "open" }, "payment" => { "gateway_type" => 1, "status_object" => { "slug" => "pending" } },
  "shipping" => { "price" => 20, "status_object" => { "slug" => "unfulfilled" }, "address" => address.merge("first_line" => "Synthetic street") },
  "variants" => [ { "price" => 124.95, "quantity" => 2, "variant" => { "id" => "synthetic-variant", "variations" => { "Size" => "S", "_private" => "do not copy" }, "product" => { "name" => "YouCan external" } } } ] } }
youcan_received = deliver.call(youcan, youcan_order, { "X-YOUCAN-TOPIC" => "order.created" }).receipt.order
assert.call("YouCan hex signature/envelope", youcan_received.total_cents == 26_990)
assert.call("YouCan variant selection survives", youcan_received.order_items.first.variant_name == "Size: S")
youcan_fallback = youcan_order.deep_dup
youcan_fallback["data"]["id"] = SecureRandom.uuid
youcan_fallback["data"]["variants"].first["variant"]["variations"] = {}
assert.call("YouCan variant identity fallback", deliver.call(youcan, youcan_fallback, { "X-YOUCAN-TOPIC" => "order.created" }).receipt.order.order_items.first.variant_name == "Variant synthetic-variant")
youcan_options = youcan_fallback.deep_dup
youcan_options["data"]["id"] = SecureRandom.uuid
youcan_options["data"]["variants"].first["variant"].merge!("options" => [ "Size", "Color" ], "values" => [ "XL", "Blue" ])
assert.call("YouCan paired options survive", deliver.call(youcan, youcan_options, { "X-YOUCAN-TOPIC" => "order.created" }).receipt.order.order_items.first.variant_name == "Size: XL / Color: Blue")
partial = { "event_name" => "order.created", "data" => { "id" => SecureRandom.uuid, "store_id" => youcan.external_store_id, "total" => 10, "currency" => "MAD" } }
assert.call("YouCan incomplete relationships rejected", deliver.call(youcan, partial, { "X-YOUCAN-TOPIC" => "order.created" }).receipt.error_code == "incomplete_payload")

[ nil, {}, [], "NaN", "Infinity", -1, "0.001", "9" * 100, 1.0e100 ].each_with_index do |amount, index|
  invalid = shopify.merge("id" => "invalid-money-#{index}", "total_price" => amount)
  rejection = deliver.call(connection, invalid, headers).receipt
  assert.call("invalid money shape #{index} rejected safely", rejection.status == "rejected" && rejection.order_id.nil?)
end
begin
  deliver.call(youcan, { "event_name" => "order.created", "data" => [] }, { "X-YOUCAN-TOPIC" => "order.created" })
  raise "invalid envelope accepted"
rescue Connections::WebhookIntake::Error => error
  assert.call("malformed YouCan envelope rejected safely", error.status == 422)
end

# Real database contention verifies the connection lock and unique identity.
ready = Queue.new
release = Queue.new
workers = 2.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      ready << true
      release.pop
      deliver.call(StoreConnection.find(connection.id), shopify.merge("id" => 999), headers).receipt.order_id
    end
  end
end
2.times { ready.pop }
2.times { release << true }
ids = workers.map(&:value)
assert.call("concurrent delivery creates one order", ids.uniq.one? && connection.external_order_receipts.where(external_id: "999").count == 1)
puts "Connected store intake smoke: #{checks} checks passed"
