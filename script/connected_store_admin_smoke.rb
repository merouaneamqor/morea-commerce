# frozen_string_literal: true

raise "Connected store admin smoke requires isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = ->(message, condition) { raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(5)
  password = SecureRandom.hex(12)
  secret = "synthetic-signing-secret-#{suffix}"
  replacement = "replacement-signing-secret-#{suffix}"
  store = Store.create!(name: "External operations", slug: "external-http-#{suffix}", currency: "MAD", storefront_enabled: false)
  other = Store.create!(name: "Other operations", slug: "other-http-#{suffix}", currency: "MAD")
  staff = store.users.create!(email: "operator-#{suffix}@example.test", password: password, admin: true)
  root = User.create!(email: "platform-#{suffix}@example.test", password: password, admin: true, super_admin: true)
  foreign = other.store_connections.create!(name: "Foreign source", provider: "woocommerce", external_domain: "other.example.test", webhook_secret: secret)
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{store.slug}.#{Store.base_domain}"
  http.get "/admin/store_connections"
  assert.call("connections require login", http.response.redirect?)
  http.post "/admin/login", params: { email: staff.email, password: password }
  %w[fr en ar].each do |locale|
    http.get "/admin/store_connections/new", params: { locale: locale }
    doc = Nokogiri::HTML(http.response.body)
    assert.call("localized connection form #{locale}", http.response.status == 200 && !doc.at_css(".translation_missing") && doc.at_css("html")["dir"] == (locale == "ar" ? "rtl" : "ltr"))
  end
  attrs = { name: "Woo admin source", provider: "woocommerce", external_domain: "admin-#{suffix}.example.test", webhook_secret: secret, store_id: other.id, active: false }
  http.post "/admin/store_connections", params: { store_connection: attrs }
  created = store.store_connections.find_by!(name: "Woo admin source")
  assert.call("create connection tenant owned and awaiting verification", http.response.redirect? && created.active? && created.store_id == store.id)
  api_connection = store.store_connections.create!(name: "Shopify API source", provider: "shopify", external_domain: "synthetic-#{suffix}.myshopify.com", shopify_oauth: true)
  %w[fr en ar].each do |locale|
    http.get "/admin/store_connections/#{api_connection.id}", params: { locale: locale }
    doc = Nokogiri::HTML(http.response.body)
    assert.call("localized API connection setup #{locale}", http.response.status == 200 && !doc.at_css(".translation_missing") && !doc.at_css("#webhook-url") && doc.at_css("input[name='operation'][value='authorize_shopify']"))
    assert.call("Shopify no longer requests a webhook secret #{locale}", !doc.at_css("input[name='store_connection[webhook_secret]']"))
    assert.call("Shopify merchants do not enter app credentials #{locale}", !doc.at_css("input[name='store_connection[shopify_client_id]']") && !doc.at_css("input[name='store_connection[shopify_client_secret]']"))
  end
  http.get "/admin/store_connections/#{foreign.id}"
  assert.call("foreign connection hidden", http.response.status == 404)
  http.patch "/admin/store_connections/#{foreign.id}", params: { operation: "disconnect" }
  assert.call("foreign connection cannot be changed", http.response.status == 404 && foreign.reload.active?)
  http.post "/admin/store_connections", params: { store_connection: attrs.merge(external_domain: "https://wrong.example/path") }
  assert.call("invalid provider domain has visible validation", http.response.status == 422 && !http.response.body.include?(secret))

  # Preserve existing signed intake independently of the new API setup UI.
  connection = store.store_connections.create!(name: "Legacy Shopify source", provider: "shopify", external_domain: "legacy-#{suffix}.myshopify.com", webhook_secret: secret)
  # End-to-end signed webhook delivery on the apex, with complete parameter
  # filtering even for provider-defined custom fields outside known PII paths.
  webhook = ActionDispatch::Integration::Session.new(Rails.application)
  webhook.host! Store.base_domain
  path = "/webhooks/store_orders/#{connection.token}"
  payload = { id: 321, currency: "MAD", financial_status: "pending", payment_gateway_names: [ "Cash on Delivery (COD)" ], total_tax: "0.00", total_discounts: "0.00", total_price: "249.90",
    shipping_address: { name: "Synthetic buyer", phone: "0612345678", city: "Casablanca", address1: "Synthetic street", country_code: "MA" },
    total_shipping_price_set: { shop_money: { amount: "0.00", currency_code: "MAD" } },
    line_items: [ { name: "External product", quantity: 2, price: "124.95", variant_title: "Size M" } ],
    arbitrary_custom_field: "PRIVATE-MARKER-#{suffix}" }
  body = JSON.generate(payload)
  headers = { "CONTENT_TYPE" => "application/json", "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain }
  sign = ->(value) { Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", value, body)) }
  webhook.post path, params: body, headers: headers
  assert.call("unsigned delivery rejected", webhook.response.status == 401 && store.orders.empty?)
  instrumentation = []
  listener = ActiveSupport::Notifications.subscribe("start_processing.action_controller") { |*args| instrumentation << args.last[:params] }
  begin
    webhook.post path, params: body, headers: headers.merge("X-Shopify-Hmac-SHA256" => sign.call(secret))
  ensure
    ActiveSupport::Notifications.unsubscribe(listener)
  end
  assert.call("signed order received without storefront", webhook.response.status == 200 && store.orders.count == 1)
  assert.call("complete provider params filtered before logging", instrumentation.any? && !instrumentation.to_json.include?(payload[:arbitrary_custom_field]) && !instrumentation.to_json.include?("Synthetic street"))
  order = store.orders.first
  webhook.post path, params: body, headers: headers.merge("X-Shopify-Hmac-SHA256" => sign.call(secret))
  assert.call("HTTP replay does not duplicate", webhook.response.status == 200 && webhook.response.parsed_body["replayed"] && store.orders.count == 1)
  http.get "/admin/orders", params: { connection_id: connection.id }
  doc = Nokogiri::HTML(http.response.body)
  assert.call("source filter and label render", http.response.status == 200 && http.response.body.include?(order.number) && http.response.body.include?(connection.name))
  assert.call("status tabs keep source filter", doc.css("a.admin-tab").all? { |link| link["href"].include?("connection_id=#{connection.id}") })
  http.get "/admin/orders", params: { connection_id: foreign.id }
  assert.call("foreign source filter denied", http.response.status == 404)
  http.get "/admin/orders/#{order.id}"
  assert.call("snapshot order view renders", http.response.status == 200 && http.response.body.include?("Size M"))
  token = store.generate_api_token!
  webhook.post "/graphql", params: { query: "{ orders { number items { productSlug productName } } }" }, headers: { "Authorization" => "Bearer #{token}" }, as: :json
  json = webhook.response.parsed_body
  assert.call("GraphQL snapshot product slug nullable", webhook.response.status == 200 && json["errors"].nil? && json.dig("data", "orders", 0, "items", 0, "productSlug").nil?)
  http.patch "/admin/orders/#{order.id}", params: { order: { lines: [ { product_id: foreign.id, quantity: 1 } ], name: "Changed" } }
  assert.call("commercial edits cannot replace external prices", http.response.redirect? && order.reload.total_cents == 24_990)
  http.post "/admin/orders/#{order.id}/duplicate"
  assert.call("snapshot duplicate denied without partial order", http.response.redirect? && store.orders.count == 1)
  connection.with_lock { connection.update!(webhook_secret: replacement, verified_at: nil, last_error_code: nil) }
  assert.call("legacy secret rotation preserves identity and clears verification", connection.reload.webhook_secret == replacement && connection.verified_at.nil? && connection.external_order_receipts.count == 1)
  webhook.post path, params: body, headers: headers.merge("X-Shopify-Hmac-SHA256" => sign.call(secret))
  assert.call("old secret revoked", webhook.response.status == 401)
  webhook.post path, params: body, headers: headers.merge("X-Shopify-Hmac-SHA256" => sign.call(replacement))
  assert.call("rotated secret can replay without duplicate", webhook.response.status == 200 && store.orders.count == 1 && connection.reload.verified_at.present?)
  http.patch "/admin/store_connections/#{connection.id}", params: { operation: "disconnect" }
  webhook.post path, params: body, headers: headers.merge("X-Shopify-Hmac-SHA256" => sign.call(replacement))
  assert.call("disconnected source rejects delivery", webhook.response.status == 410 && connection.reload.external_order_receipts.count == 1)
  http.patch "/admin/store_connections/#{connection.id}", params: { operation: "reconnect" }
  assert.call("reconnect awaits signed verification", connection.reload.active? && connection.verified_at.nil?)
  platform = ActionDispatch::Integration::Session.new(Rails.application)
  platform.host! Store.base_domain
  platform.post "/admin/login", params: { email: root.email, password: password }
  platform.get "/admin/store_connections"
  assert.call("platform-only session cannot query tenant sources", platform.response.status == 404)

  # WooCommerce's exact unsigned activation ping must never import or verify.
  woo = store.store_connections.create!(name: "Woo source", provider: "woocommerce", external_domain: "woo.example.test", webhook_secret: secret)
  webhook.post "/webhooks/store_orders/#{woo.token}", params: "webhook_id=123", headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
  assert.call("Woo activation probe acknowledged without verification", webhook.response.status == 200 && woo.reload.verified_at.nil? && woo.external_order_receipts.empty?)
  raise ActiveRecord::Rollback
end
puts "Connected store admin smoke: #{checks} checks passed"
