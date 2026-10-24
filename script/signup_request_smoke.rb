# frozen_string_literal: true

raise "Signup smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

# Capture Discord payloads instead of calling the network.
captured = []
DiscordNotifier.prepend(Module.new do
  define_method(:post_json) { |url, payload| captured << [ url, payload ]; true }
end)

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  password = SecureRandom.hex(12)
  super_admin = User.create!(email: "root-#{suffix}@example.test", name: "Root", password: password, admin: true, super_admin: true)
  store = Store.create!(slug: "signup-#{suffix}", name: "Signup CI", currency: "MAD")
  staff = store.users.create!(email: "staff-#{suffix}@example.test", password: password, admin: true)

  apex = lambda do
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.host! Store.base_domain
    http
  end
  form = { access_request: { store_name: "Atelier #{suffix}", email: "Owner-#{suffix}@Example.test ", phone: "0612345678" } }

  http = apex.call
  http.get "/signup"
  assert.call("signup form renders on the apex", http.response.status == 200 && http.response.body.include?("access_request[email]"))
  %w[fr en ar].each do |locale|
    http.get "/signup", params: { locale: locale }
    assert.call("signup renders in #{locale}", http.response.status == 200 && http.response.body.include?(%(lang="#{locale}")))
  end
  tenant = ActionDispatch::Integration::Session.new(Rails.application)
  tenant.host! "#{store.slug}.#{Store.base_domain}"
  tenant.get "/signup"
  assert.call("store hosts have no signup page", tenant.response.status == 404)

  # Create
  http.post "/signup", params: form
  assert.call("valid request redirects to thanks", http.response.redirect? && http.response.location.include?("/signup/thanks"))
  request = AccessRequest.find_by!(email: "owner-#{suffix}@example.test")
  assert.call("request stored pending and normalized", request.pending? && request.store_name == "Atelier #{suffix}" && request.store_id.nil?)
  assert.call("no store or user created by signup", Store.where(name: request.store_name).none? && User.where(email: request.email).none?)
  assert.call("Discord job enqueued once", ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "AccessRequestNotifyJob" } == 1)
  http.get "/signup/thanks"
  assert.call("thanks page renders", http.response.status == 200)

  # Discord payload
  ENV["PLATFORM_DISCORD_WEBHOOK_URL"] = "https://discord.example.test/api/webhooks/1/x"
  AccessRequestNotifyJob.new.perform(request.id)
  url, payload = captured.last
  assert.call("Discord receives the request", url.include?("discord.example.test") && payload[:content].include?(request.store_name))
  assert.call("Discord embed has contact fields", payload[:embeds].first[:fields].map { |f| f[:value] }.include?(request.email))
  assert.call("Discord message cannot ping anyone", payload[:allowed_mentions] == { parse: [] })
  assert.call("Discord link points to the platform admin", payload[:embeds].first[:url].end_with?("/admin/access_requests"))
  ENV.delete("PLATFORM_DISCORD_WEBHOOK_URL")
  before = captured.size
  AccessRequestNotifyJob.new.perform(request.id)
  assert.call("no webhook configured means no call and no error", captured.size == before)

  # Validation, duplicates, honeypot
  http.post "/signup", params: { access_request: { store_name: "x", email: "not-an-email" } }
  assert.call("invalid request re-renders with field errors", http.response.status == 422 && http.response.body.include?("email-error"))
  count = AccessRequest.count
  http.post "/signup", params: form
  assert.call("duplicate pending email looks like success", http.response.redirect? && AccessRequest.count == count)
  http.post "/signup", params: form.merge(website: "http://spam.example", access_request: form[:access_request].merge(email: "bot-#{suffix}@example.test"))
  assert.call("honeypot stores nothing", http.response.redirect? && AccessRequest.where(email: "bot-#{suffix}@example.test").none?)

  # Throttle
  spammer = apex.call
  AccessRequest::MAX_PER_IP_PER_HOUR.times do |i|
    AccessRequest.create!(store_name: "Spam #{i}", email: "spam#{i}-#{suffix}@example.test", ip: "203.0.113.9")
  end
  assert.call("throttle counts by IP", AccessRequest.throttled?("203.0.113.9") && !AccessRequest.throttled?("203.0.113.10"))
  spammer.post "/signup", params: { access_request: { store_name: "Another", email: "another-#{suffix}@example.test" } },
    headers: { "REMOTE_ADDR" => "203.0.113.9" }
  assert.call("too many requests from one IP are refused", spammer.response.status == 429)
  assert.call("a different IP is not throttled", begin
    spammer.post "/signup", params: { access_request: { store_name: "Another", email: "another-#{suffix}@example.test" } },
      headers: { "REMOTE_ADDR" => "203.0.113.10" }
    spammer.response.redirect?
  end)
  AccessRequest.where(ip: "203.0.113.9").delete_all
  AccessRequest.where(email: "another-#{suffix}@example.test").delete_all

  # Platform admin dashboard
  admin = apex.call
  admin.get "/admin/access_requests"
  assert.call("access requests need a login", admin.response.redirect?)
  admin.post "/admin/login", params: { email: staff.email, password: password }
  staff_http = ActionDispatch::Integration::Session.new(Rails.application)
  staff_http.host! "#{store.slug}.#{Store.base_domain}"
  staff_http.post "/admin/login", params: { email: staff.email, password: password }
  staff_http.get "/admin/access_requests"
  assert.call("store staff cannot see access requests", staff_http.response.redirect?)

  admin.post "/admin/login", params: { email: super_admin.email, password: password }
  admin.get "/admin/platform"
  assert.call("platform overview keeps pending requests out of workspace records", admin.response.status == 200 && !admin.response.body.include?(request.store_name) && !admin.response.body.include?(request.email))
  doc = Nokogiri::HTML(admin.response.body)
  assert.call("dashboard links to the separate request queue with pending count", doc.at_css("[data-access-requests-count='#{AccessRequest.pending.count}']") && doc.at_css(".admin-sidebar a[href='/admin/access_requests']"))
  admin.get "/admin/access_requests"
  assert.call("list shows the request", admin.response.status == 200 && admin.response.body.include?(request.store_name))
  %w[fr en ar].each do |locale|
    admin.get "/admin/platform", params: { locale: locale }
    doc = Nokogiri::HTML(admin.response.body)
    assert.call("localized workspace overview separates access requests #{locale}", admin.response.status == 200 && doc.at_css("#workspaces") && !doc.at_css("#access-requests") && !admin.response.body.include?(request.email) && !doc.at_css(".translation_missing"))
    assert.call("platform locale and direction #{locale}", doc.at_css("html")["lang"] == locale && doc.at_css("html")["dir"] == (locale == "ar" ? "rtl" : "ltr"))
    admin.get "/admin/access_requests", params: { locale: locale }
    doc = Nokogiri::HTML(admin.response.body)
    assert.call("request timestamps render without missing translations #{locale}", admin.response.status == 200 && doc.at_css("time[datetime]") && !admin.response.body.match?(/translation missing/i) && !doc.at_css(".translation_missing"))
    assert.call("approval reviews workspace access rather than creating a storefront #{locale}", doc.at_css("form[action='/admin/access_requests/#{request.id}/approve']")&.text&.include?(I18n.t("platform_admin.review_request", locale: locale)) && !admin.response.body.include?("Create store"))
  end

  # Approve through store creation
  admin.post "/admin/access_requests/#{request.id}/approve"
  assert.call("approve opens the prefilled store form", admin.response.redirect? && admin.response.location.include?("access_request_id=#{request.id}"))
  assert.call("review alone does not approve or create a workspace", request.reload.pending? && request.store.nil? && !Store.exists?(name: request.store_name))
  admin.get "/admin/tenants/new", params: { access_request_id: request.id }
  assert.call("form is prefilled", admin.response.body.include?(request.store_name) && admin.response.body.include?(request.email))
  assert.call("approval form creates a workspace rather than claiming to create a storefront", admin.response.body.include?(I18n.t("platform_admin.approve_and_create_workspace")) && !admin.response.body.include?("Create store"))
  admin.post "/admin/tenants", params: { access_request_id: request.id,
    store: { name: request.store_name, slug: "atelier-#{suffix}", email: request.email, currency: "MAD", billing_interval: "monthly", billing_status: "trial", billing_amount_dh: "0" },
    admin: { email: request.email, password: "Pass-#{password}" } }
  assert.call("store created: #{admin.response.status}", Store.exists?(slug: "atelier-#{suffix}"))
  request.reload
  assert.call("request approved and linked", request.status == "approved" && request.store&.slug == "atelier-#{suffix}" && request.reviewed_by_id == super_admin.id)
  admin.post "/admin/access_requests/#{request.id}/approve"
  assert.call("approved request cannot be approved again", admin.response.location.end_with?("/admin/access_requests"))

  # Reject
  other = AccessRequest.create!(store_name: "Nope", email: "nope-#{suffix}@example.test")
  admin.post "/admin/access_requests/#{other.id}/reject"
  assert.call("reject records the reviewer", other.reload.status == "rejected" && other.reviewed_by_id == super_admin.id)
  assert.call("rejected request creates no store", Store.where(name: "Nope").none?)

  puts "Signup request checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
