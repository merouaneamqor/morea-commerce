# frozen_string_literal: true

raise "COD request smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  store = Store.create!(slug: "cod-http-#{suffix}", name: "COD HTTP CI", currency: "MAD")
  other = Store.create!(slug: "cod-other-#{suffix}", name: "Other COD CI", currency: "MAD")
  product = store.products.create!(name: "HTTP Product", slug: "http-product", status: "active", price_cents: 10_000, stock: 10, track_inventory: true)
  foreign = other.products.create!(name: "Other Product", slug: "other-product", status: "active", price_cents: 10_000, stock: 10)
  staff = store.users.create!(email: "cod-#{suffix}@example.test", password: "test-password", admin: true)
  token = store.generate_api_token!
  other_token = other.generate_api_token!
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{store.slug}.lvh.me"
  attrs = { name: "CI Buyer", phone: "0612345678", city: "Casablanca", address: "CI test address", lines: [ { product_id: product.id, quantity: 2 } ] }
  payload = { source: "ci", external_id: "external-1", order: attrs }
  headers = { "Authorization" => "Bearer #{token}" }

  http.post "/api/v1/order_imports", params: payload, as: :json
  assert.call("unauthenticated import rejected", http.response.status == 401)
  http.post "/api/v1/order_imports", params: payload, headers: headers, as: :json
  assert.call("first import created: #{http.response.status} #{http.response.body}", http.response.status == 201)
  response = http.response.parsed_body
  number = response.dig("order", "number")
  assert.call("response excludes customer data", response.keys.sort == %w[created order replayed] && response["order"].keys.sort == %w[id number status])
  http.post "/api/v1/order_imports", params: payload, headers: headers, as: :json
  assert.call("replayed request is successful", http.response.status == 200 && http.response.parsed_body["replayed"])
  assert.call("one imported order", store.orders.count == 1)
  http.post "/api/v1/order_imports", params: payload.merge(external_id: "overflow", order: attrs.merge(shipping_dh: "9" * 400)), headers: headers, as: :json
  assert.call("monetary overflow rejected without records", http.response.status == 422 && store.orders.count == 1)
  assert.call("import leaves stock available", product.reload.stock == 10)
  http.post "/api/v1/order_imports", params: payload.merge(external_id: "foreign", order: attrs.merge(lines: [ { product_id: foreign.id, quantity: 1 } ])), headers: headers, as: :json
  assert.call("foreign product rejected", http.response.status == 422)
  http.post "/api/v1/order_imports", params: payload.merge(store_id: other.id), headers: headers, as: :json
  assert.call("body cannot change tenant", http.response.status == 422)
  http.post "/api/v1/order_imports", params: payload, headers: { "Authorization" => "Bearer #{other_token}" }, as: :json
  assert.call("token cannot import another store catalog", http.response.status == 422 && other.orders.count.zero?)

  http.get "/admin/confirmations"
  assert.call("queue requires login", http.response.redirect?)
  http.post "/admin/login", params: { email: staff.email, password: "test-password" }
  assert.call("staff can sign in", http.response.redirect?)
  http.get "/admin/confirmations"
  assert.call("confirmation queue renders imported order", http.response.status == 200 && http.response.body.include?(number))
  order = store.orders.find_by!(number: number)
  %w[fr en ar].each do |locale|
    http.get "/admin/confirmations", params: { locale: locale }
    doc = Nokogiri::HTML(http.response.body)
    assert.call("localized queue #{locale}", http.response.status == 200 && doc.at_css("html")["lang"] == locale && !doc.at_css(".translation_missing"))
    assert.call("queue direction #{locale}", doc.at_css("html")["dir"] == (locale == "ar" ? "rtl" : "ltr"))
  end
  http.post "/admin/confirmations/#{order.id}/claim"
  assert.call("claim request redirects", http.response.redirect?)
  stale_order = Order.find(order.id)
  http.post "/admin/confirmations/#{order.id}/outcome", params: { outcome: "confirmed", notes: "Confirmed by CI" }
  assert.call("confirmation request succeeds", http.response.redirect? && order.reload.status == "confirmed")
  assert.call("confirmation reserves stock once", product.reload.stock == 8)
  stale_rejected = false
  begin
    stale_order.transition_to!("confirmed")
  rescue ArgumentError
    stale_rejected = true
  end
  assert.call("stale legacy confirmation rejected", stale_rejected && product.reload.stock == 8)
  http.post "/admin/confirmations/#{order.id}/outcome", params: { outcome: "confirmed" }
  assert.call("repeated confirmation does not reserve twice", product.reload.stock == 8)
  http.host! "#{other.slug}.lvh.me"
  http.get "/admin/confirmations"
  assert.call("session cannot enter another tenant queue", http.response.redirect?)

  # Customer-facing routes stay public, localized and tenant-scoped.
  [ store, other ].each do |tenant|
    http.host! "#{tenant.slug}.lvh.me"
    %w[fr en ar].each do |locale|
      http.get "/#{locale}"
      assert.call("public tenant storefront #{locale}", http.response.status == 200 && !http.response.body.include?("Confirmations</span>"))
    end
  end
  http.host! "#{store.slug}.lvh.me"
  http.post "/en/cart/add_item", params: { product_id: product.id, quantity: 1 }
  assert.call("public add-to-cart works", http.response.redirect? || http.response.successful?)
  http.get "/en/checkout"
  assert.call("customer checkout remains public", http.response.status == 200)
  http.post "/en/checkout", params: { checkout: attrs.except(:lines) }
  assert.call("public COD checkout places order", http.response.redirect? && store.orders.count == 2)
  assert.call("checkout order remains new", store.orders.order(:id).last.status == "new")
  puts "COD requests: #{checks} checks passed"
  raise ActiveRecord::Rollback
end
