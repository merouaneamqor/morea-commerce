# frozen_string_literal: true

raise "Merchant dashboard smoke requires an isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = ->(message, condition) { raise message unless condition; checks += 1 }

# All fixtures are synthetic and rolled back, including HTTP session requests.
# Direct fixture statuses represent historical records; no carrier is configured.
ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(5)
  password = SecureRandom.hex(16)
  storefront = Store.create!(slug: "dashboard-shop-#{suffix}", name: "Synthetic boutique", currency: "MAD")
  external = Store.create!(slug: "dashboard-external-#{suffix}", name: "Synthetic operations", currency: "MAD", storefront_enabled: false)
  foreign = Store.create!(slug: "dashboard-foreign-#{suffix}", name: "Foreign dashboard", currency: "MAD")
  staff = storefront.users.create!(email: "dashboard-#{suffix}@example.test", password: password, admin: true)
  external_staff = external.users.create!(email: "external-#{suffix}@example.test", password: password, admin: true)
  platform_staff = User.create!(email: "dashboard-root-#{suffix}@example.test", password: password, admin: true, super_admin: true)
  now = Time.find_zone!("Africa/Casablanca").local(2026, 10, 24, 12, 30)
  start = now.beginning_of_day - 6.days
  summary = ->(store, period = "7") { Admin::DashboardSummary.new(store: store, period: period, now: now) }

  empty = summary.call(storefront)
  assert.call("new boutique has zero exact totals", empty.mode == "storefront" && empty.orders_count.zero? && empty.order_value_cents.zero?)
  assert.call("new boutique has no invented activity", empty.recent_orders.empty? && !empty.has_orders && !empty.has_products && empty.low_stock_count.zero?)
  external_empty = summary.call(external)
  assert.call("external workspace needs no local catalog", external_empty.mode == "connected" && !external_empty.has_products && !external_empty.has_tracked_inventory)
  assert.call("external workspace has no cart metric", external_empty.active_carts_count.nil? || external_empty.active_carts_count.zero?)
  assert.call("unsupported period falls back to seven days", summary.call(storefront, "invalid").period == "7" && summary.call(storefront, "999").days == 7)
  assert.call("calendar window uses Casablanca boundaries", empty.starts_at == start && empty.ends_at == now && empty.days == 7)
  initial_http = ActionDispatch::Integration::Session.new(Rails.application)
  initial_http.host! "#{storefront.slug}.#{Store.base_domain}"
  initial_http.post "/admin/login", params: { email: staff.email, password: password }
  initial_http.get "/admin", params: { locale: "en" }
  initial_doc = Nokogiri::HTML(initial_http.response.body)
  assert.call("new boutique dashboard renders its setup state", initial_http.response.status == 200 && initial_doc.at_css('[data-dashboard-mode="storefront"]') && initial_doc.at_css("[data-dashboard-storefront]"))

  make_order = lambda do |store, cents:, at:, status: "new", archived: false, sendit_code: nil|
    customer = store.customers.first || store.customers.create!(name: "Synthetic customer", phone: "0612345678", city: "Casablanca")
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: "Casablanca", customer_address: "Synthetic address", total_cents: cents, subtotal_cents: cents,
      currency: "MAD", status: status, created_at: at, updated_at: at, archived_at: (now if archived), sendit_code: sendit_code)
  end
  # Boundary, archive, terminal, future and another-tenant records deliberately
  # differ: the dashboard must describe an order cohort, not a ledger balance.
  first = make_order.call(storefront, cents: 12_345, at: start)
  delivered = make_order.call(storefront, cents: 20_099, at: now - 1.day, status: "delivered")
  make_order.call(storefront, cents: 3_333, at: now - 2.days, status: "cancelled")
  archived = make_order.call(storefront, cents: 4_444, at: now - 3.days, archived: true)
  old = make_order.call(storefront, cents: 555, at: start - 1.second)
  make_order.call(storefront, cents: 999_999, at: now + 1.second, status: "delivered")
  foreign_order = make_order.call(foreign, cents: 888_888, at: now - 1.hour)
  cohort = summary.call(storefront)
  assert.call("cohort includes exact lower bound and archived history, excludes future and foreign orders", cohort.orders_count == 4 && cohort.order_value_cents == 40_221)
  assert.call("terminal counts are statuses of the selected creation cohort", cohort.delivered_count == 1 && cohort.cancelled_count == 1)
  thirty = summary.call(storefront, "30")
  assert.call("thirty days includes older order with exact cents", thirty.days == 30 && thirty.orders_count == 5 && thirty.order_value_cents == 40_776)
  alternate_currency = make_order.call(storefront, cents: 777, at: now - 1.hour, status: "delivered")
  alternate_currency.update!(currency: "EUR")
  canonical_currency = make_order.call(storefront, cents: 123, at: now - 1.hour, status: "delivered")
  canonical_currency.update!(currency: "DH")
  money = summary.call(storefront)
  assert.call("different currencies stay separate and DH normalizes to MAD", money.order_values == { "MAD" => 40_344, "EUR" => 777 } && money.order_value_cents == 40_344)

  # Each side of local midnight differs from UTC midnight in Casablanca.
  midnight = now.beginning_of_day
  yesterday = make_order.call(external, cents: 101, at: midnight - 1.second)
  today = make_order.call(external, cents: 203, at: midnight)
  make_order.call(external, cents: 307, at: now)
  make_order.call(external, cents: 409, at: now + 1.second)
  local_window = summary.call(external)
  assert.call("current local day includes midnight and now", local_window.orders_count == 3 && local_window.order_value_cents == 611)
  # Use a period start at the local boundary to catch accidental UTC truncation.
  yesterday.update!(created_at: start - 1.second)
  today.update!(created_at: start)
  assert.call("local calendar boundary is inclusive", summary.call(external).order_value_cents == 510)

  callback = make_order.call(storefront, cents: 100, at: now - 45.days)
  callback.create_order_confirmation!(store: storefront, disposition: "callback", callback_at: now)
  future_callback = make_order.call(storefront, cents: 100, at: now - 45.days)
  future_callback.create_order_confirmation!(store: storefront, disposition: "callback", callback_at: now + 1.hour)
  archived.create_order_confirmation!(store: storefront, disposition: "callback", callback_at: now - 1.hour)
  delivered.create_order_confirmation!(store: storefront, disposition: "callback", callback_at: now - 1.hour)
  make_order.call(storefront, cents: 100, at: now - 45.days, sendit_code: "synthetic-parcel-#{suffix}")
  Order::PROBLEM_STATUSES.each { |status| make_order.call(storefront, cents: 100, at: now - 45.days, status: status) }
  make_order.call(storefront, cents: 100, at: now - 45.days, status: "address_issue", archived: true)
  make_order.call(foreign, cents: 100, at: now, status: "address_issue")
  workload = summary.call(storefront)
  assert.call("pending work spans all time but excludes archived and carrier parcels", workload.pending_count == 4)
  assert.call("due callbacks exclude future, archived and terminal orders", workload.callbacks_due_count == 1)
  assert.call("delivery issues span all time and stay tenant scoped", workload.delivery_issues_count == 3)

  make_connection = lambda do |store, provider, name, **attributes|
    domain = provider == "shopify" ? "#{name.downcase}-#{suffix}.myshopify.com" : "#{name.downcase}-#{suffix}.example.test"
    store.store_connections.create!({ provider: provider, name: name, external_domain: domain,
      external_store_id: (SecureRandom.uuid if provider == "youcan"), webhook_secret: "synthetic-secret-#{suffix}" }.merge(attributes))
  end
  configured = make_connection.call(storefront, "shopify", "Awaiting")
  verified = make_connection.call(storefront, "woocommerce", "Verified", verified_at: now - 1.day, last_received_at: now - 1.hour)
  failed = make_connection.call(storefront, "youcan", "NeedsAttention", verified_at: now - 2.days, last_error_code: "incomplete_payload")
  disconnected = make_connection.call(storefront, "woocommerce", "Disconnected", active: false, verified_at: now - 3.days)
  foreign_connection = make_connection.call(foreign, "shopify", "ForeignConnection")
  verified.external_order_receipts.create!(external_id: "accepted-synthetic", status: "accepted", order: delivered, received_at: now)
  failed.external_order_receipts.create!(external_id: "rejected-synthetic", status: "rejected", error_code: "incomplete_payload", received_at: now)
  foreign_connection.external_order_receipts.create!(external_id: "foreign-rejected", status: "rejected", error_code: "incomplete_payload", received_at: now)
  connected = summary.call(storefront)
  assert.call("boutique plus sources uses combined workspace", connected.mode == "combined" && connected.connections_count == 4)
  assert.call("current receipt failures remain tenant scoped", connected.rejected_count == 1)
  assert.call("channel order totals retain exact cents", connected.source_stats.fetch(verified.id).slice(:orders_count, :order_value_cents) == { orders_count: 1, order_value_cents: 20_099 })
  assert.call("channel rejected receipt count visible", connected.source_stats.fetch(failed.id)[:rejected_count] == 1)
  assert.call("configured is never verified before signed delivery", configured.connection_state == "configured" && verified.connection_state == "verified" && disconnected.connection_state == "disconnected")
  assert.call("error sources receive attention priority", connected.connections.first.id == failed.id)
  5.times { |index| make_connection.call(storefront, "woocommerce", "Extra#{index}", active: false) }
  assert.call("source list bounded without losing total", summary.call(storefront).connections.size == 6 && summary.call(storefront).connections_count == 9)

  make_product = lambda do |name, **attributes|
    storefront.products.create!({ name: name, slug: "#{name.parameterize}-#{suffix}", status: "active", price_cents: 1_099, stock: 0, track_inventory: true }.merge(attributes))
  end
  6.times { |index| make_product.call("Low stock #{index}") }
  make_product.call("Untracked", track_inventory: false)
  make_product.call("Draft stock", status: "draft")
  variant_product = make_product.call("Variant stock", stock: 100)
  variant_product.product_variants.create!(name: "Low active variant", stock: 1)
  variant_product.product_variants.create!(name: "Second low variant", stock: 0)
  stocked = make_product.call("Inactive variants only", stock: 0)
  stocked.product_variants.create!(name: "Inactive low variant", stock: 0, active: false)
  inventory = summary.call(storefront)
  assert.call("low stock uses active tracked catalog and distinct variant products", inventory.low_stock_count == 7 && inventory.low_stock.size == 5)
  assert.call("catalog presence and stock availability are separate flags", inventory.has_products && inventory.has_tracked_inventory)
  10.times { |index| make_order.call(storefront, cents: 1, at: now - index.minutes) }
  recent = summary.call(storefront).recent_orders
  assert.call("recent orders bounded and tenant scoped", recent.size == 8 && recent.all? { |order| order.store_id == storefront.id && order.created_at <= now } && recent.none?(&:archived?))

  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{storefront.slug}.#{Store.base_domain}"
  http.get "/admin"
  assert.call("dashboard requires sign in", http.response.redirect? && http.response.location.include?("/admin/login"))
  http.post "/admin/login", params: { email: staff.email, password: password }
  %w[fr en ar].each do |locale|
    http.get "/admin", params: { locale: locale, period: "30" }
    doc = Nokogiri::HTML(http.response.body)
    assert.call("localized dashboard #{locale}", http.response.status == 200 && doc.at_css("html")["dir"] == (locale == "ar" ? "rtl" : "ltr") && !doc.at_css(".translation_missing") && !http.response.body.include?("translation missing"))
    assert.call("combined channel dashboard mode #{locale}", doc.at_css('[data-dashboard-mode="combined"]') && doc.at_css("[data-dashboard-storefront]"))
    assert.call("source health names render #{locale}", [ configured, verified, failed ].all? { |connection| http.response.body.include?(connection.name) })
    assert.call("foreign dashboard details hidden #{locale}", !http.response.body.include?(foreign_order.number) && !http.response.body.include?(foreign_connection.name))
    assert.call("source secrets never rendered #{locale}", !http.response.body.include?("synthetic-secret-#{suffix}") && !http.response.body.include?(configured.token))
    http.get "/admin/store_connections/#{failed.id}", params: { locale: locale }
    assert.call("rejected delivery history opens from dashboard #{locale}", http.response.status == 200 && http.response.body.include?("incomplete_payload"))
  end
  http.get "/admin/orders", params: { attention: "delivery_issues" }
  assert.call("delivery issue destination narrows to issues", http.response.status == 200 && !http.response.body.include?(first.number) && !http.response.body.include?(delivered.number))
  # HTTP queue uses wall-clock time; decouple these checks from the fixed
  # reporting date used above, so an evening CI run cannot make a future
  # callback fixture unexpectedly due.
  callback.order_confirmation.update!(callback_at: Time.current - 1.minute)
  future_callback.order_confirmation.update!(callback_at: Time.current + 1.day)
  foreign_order.create_order_confirmation!(store: foreign, disposition: "callback", callback_at: Time.current - 1.minute)
  carrier_callback = make_order.call(storefront, cents: 100, at: Time.current - 1.day, sendit_code: "synthetic-callback-parcel-#{suffix}")
  carrier_callback.create_order_confirmation!(store: storefront, disposition: "callback", callback_at: Time.current - 1.minute)
  http.get "/admin/confirmations", params: { filter: "callbacks_due", locale: "en" }
  assert.call("callback destination shows due work", http.response.status == 200 && http.response.body.include?(callback.number))
  assert.call("callback destination excludes future, archived, terminal, carrier and foreign orders", [ future_callback, archived, delivered, carrier_callback, foreign_order ].none? { |order| http.response.body.include?(order.number) })

  external_http = ActionDispatch::Integration::Session.new(Rails.application)
  external_http.host! "#{external.slug}.#{Store.base_domain}"
  external_http.post "/admin/login", params: { email: external_staff.email, password: password }
  external_http.get "/admin", params: { locale: "en" }
  doc = Nokogiri::HTML(external_http.response.body)
  assert.call("external-only dashboard works without products or sources", external_http.response.status == 200)
  assert.call("external-only dashboard hides boutique activity", doc.at_css('[data-dashboard-mode="connected"]') && !doc.at_css("[data-dashboard-storefront]") && !doc.at_css("[data-dashboard-inventory]"))
  %w[shopify woocommerce youcan].each do |provider|
    assert.call("external workspace offers #{provider} setup", doc.css("a").any? { |link| link["href"].to_s.include?("/admin/store_connections/new") && link["href"].include?("provider=#{provider}") })
    external_http.get "/admin/store_connections/new", params: { provider: provider }
    form = Nokogiri::HTML(external_http.response.body)
    assert.call("#{provider} setup submits the selected provider", external_http.response.status == 200 && form.at_css('form input[type="hidden"][name="store_connection[provider]"]')&.[]("value") == provider)
    active_providers = form.css('a[aria-current="page"]').select { |link| link["href"].to_s.include?("/admin/store_connections/new") }
    assert.call("#{provider} setup marks its provider link current", active_providers.one? && active_providers.first["href"].include?("provider=#{provider}"))
  end
  external_http.get "/en"
  assert.call("dashboard does not publish an external-only storefront", external_http.response.status == 404 && !external.reload.storefront_enabled?)
  http.host! "#{foreign.slug}.#{Store.base_domain}"
  http.get "/admin"
  assert.call("another tenant's staff session denied", http.response.redirect? && http.response.location.include?("/admin/login"))
  platform = ActionDispatch::Integration::Session.new(Rails.application)
  platform.host! Store.base_domain
  platform.post "/admin/login", params: { email: platform_staff.email, password: password }
  platform.get "/admin"
  assert.call("platform-only session redirects without tenant queries", platform.response.redirect? && platform.response.location.include?("/admin/platform"))
  raise ActiveRecord::Rollback
end
puts "Merchant dashboard smoke: #{checks} checks passed"
