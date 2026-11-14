# frozen_string_literal: true

require "rack/test"
require "timeout"

abort "Use an isolated Rails test database" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
suffix = SecureRandom.hex(4)
store = Store.create!(slug: "audit-#{suffix}", name: "Audit store", currency: "MAD", shipping_cents: 2000)
other = Store.create!(slug: "audit-peer-#{suffix}", name: "Audit peer", currency: "MAD")
product = store.products.create!(name: "Order Fixture", status: "active", stock: 2, price_cents: 1000, track_inventory: true)
peer_product = other.products.create!(name: "Other Fixture", status: "active", price_cents: 1000)
details = { name: "Synthetic Buyer", phone: "+12025550133", city: "Fixture City", address: "1 Synthetic Address",
  privacy_accepted: "1", age_confirmed: "1" }
browser = Rack::Test::Session.new(Rails.application)
fresh = Rack::Test::Session.new(Rails.application)
host = "http://#{store.slug}.#{Store.base_domain}"
peer_host = "http://#{other.slug}.#{Store.base_domain}"

def assert(label, condition)
  raise label unless condition
end

def race(*operations)
  ready = Queue.new
  start = Queue.new
  threads = operations.map do |operation|
    Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
  end
  Timeout.timeout(15) do
    threads.size.times { ready.pop }
    threads.size.times { start << true }
    threads.map(&:value)
  end
ensure
  threads&.each { |thread| thread.kill if thread.alive? }
end

browser.get("#{host}/fr")
assert("anonymous browse did not render", browser.last_response.ok?)
browser.get("#{host}/fr/cart")
assert("empty cart did not render", browser.last_response.ok?)
assert("read requests created a cart", store.carts.count.zero?)
browser.post("#{host}/fr/cart/add_item", { product_id: peer_product.id })
assert("foreign product was accepted", browser.last_response.status == 404)
browser.post("#{host}/fr/cart/add_item", { product_id: product.id, quantity: 1 })
assert("cart add did not redirect", browser.last_response.redirect? && store.carts.count == 1)
browser.get("#{host}/fr/cart")
assert("cart did not persist", browser.last_response.body.include?(product.name))
browser.get("#{peer_host}/fr/cart")
assert("cart read crossed tenant", !browser.last_response.body.include?(product.name) && other.carts.count.zero?)
cart = store.carts.sole
item = cart.cart_items.sole
browser.patch("#{host}/fr/cart/update_item", { item_id: item.id, quantity: 3 })
assert("cart patch did not save", item.reload.quantity == 3)
browser.post("#{host}/fr/checkout", { checkout: details })
assert("unavailable quantity not rejected", browser.last_response.status == 422 && store.orders.count.zero?)
browser.patch("#{host}/fr/cart/update_item", { item_id: item.id, quantity: 1 })

# Both requests hold a copy of the same cart before either gets the lock.
operations = Array.new(2) { Cart.find(cart.id) }.map do |copy|
  -> do
    checkout = Checkout.new(**details, store: store, cart: copy)
    checkout.place_order!
  rescue ActiveModel::ValidationError => error
    [ :rejected, error.model.errors.full_messages ]
  end
end
results = race(*operations)
rejections = results.grep(Array)
assert("duplicate checkout did not produce one winner: #{rejections.inspect}", rejections.size == 1 && store.orders.count == 1)
order = store.orders.sole
assert("stock reserved before staff confirmation", product.reload.stock == 2)
assert("checkout shipping/total mismatch", order.shipping_cents == 2000 && order.total_cents == 3000)
assert("checkout left cart lines", cart.cart_items.empty?)
path = "/fr/orders/#{order.number}"
fresh.get(host + path)
assert("order number alone exposed a receipt", fresh.last_response.status == 404)
[ "", "133", "+12025550144" ].each do |guess|
  fresh.post("#{host}/fr/orders/lookup", { number: order.number, phone: guess })
  assert("invalid phone gave access", fresh.last_response.location.end_with?("/fr/orders/track"))
end
fresh.post("#{peer_host}/fr/orders/lookup", { number: order.number, phone: details[:phone] })
assert("peer tenant looked up foreign order", fresh.last_response.location.end_with?("/fr/orders/track"))
fresh.post("#{host}/fr/orders/lookup", { number: order.number, phone: details[:phone] })
assert("valid tracking lookup failed", fresh.last_response.status == 303)
fresh.get(host + path)
assert("verified order did not render privately", fresh.last_response.ok? && fresh.last_response.headers["cache-control"].include?("no-store"))
fresh.get(peer_host + path)
assert("verified order leaked across tenant", fresh.last_response.status == 404)

# Both contenders start from stale copies, so the test detects a missing row reload even on a fast machine.
first, second = Array.new(2) { Order.find(order.id) }
confirm = ->(candidate) do
  candidate.transition_to!("confirmed")
  :confirmed
rescue ArgumentError => error
  raise unless error.message.start_with?("Invalid transition confirmed")

  :rejected
end
confirmations = race(-> { confirm.call(first) }, -> { confirm.call(second) })
assert("same order reserved stock twice", confirmations.tally == { confirmed: 1, rejected: 1 } &&
  product.reload.stock == 1 && order.inventory_movements.count == 1)
a, b = Array.new(2) { Product.find(product.id) }
decrement = ->(target) do
  Inventory::Adjuster.adjust!(product: target, quantity: -1, reason: "manual_adjustment")
  :reserved
rescue Inventory::Adjuster::Error
  :rejected
end
outcomes = race(-> { decrement.call(a) }, -> { decrement.call(b) })
assert("concurrent stock decrements oversold", outcomes.tally == { reserved: 1, rejected: 1 } && product.reload.stock.zero?)

# Exercise successful submission via HTTP too, including session authorization after redirect.
product.update!(stock: 5)
browser.post("#{host}/fr/cart/add_item", { product_id: product.id })
browser.post("#{host}/fr/checkout", { checkout: details })
assert("successful checkout did not redirect", browser.last_response.status == 303)
browser.follow_redirect!
assert("checkout redirect did not authorize its receipt", browser.last_response.ok?)
browser.post("#{peer_host}/fr/cart/add_item", { product_id: peer_product.id })
browser.get("#{peer_host}/fr/checkout")
assert("checkout recalled a different tenant's customer", browser.last_response.ok? &&
  !browser.last_response.body.include?(details[:address]) && !browser.last_response.body.include?(details[:phone]))

puts "Storefront regression passed: cart, checkout, inventory, order privacy and tenant boundaries"
