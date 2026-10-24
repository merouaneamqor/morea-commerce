# frozen_string_literal: true

raise "Optional storefront smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(5)
  password = "Test-#{SecureRandom.hex(12)}"
  root = User.create!(email: "workspace-root-#{suffix}@example.test", password: password, admin: true, super_admin: true)
  legacy = Store.create!(slug: "legacy-#{suffix}", name: "Existing store", currency: "MAD")
  assert.call("existing creation defaults to a published storefront", legacy.storefront_enabled?)
  assert.call("legacy signup defaults to storefront", AccessRequest.new.storefront_enabled?)

  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! Store.base_domain
  %w[fr en ar].each do |locale|
    http.get "/signup", params: { locale: locale }
    doc = Nokogiri::HTML(http.response.body)
    choices = doc.css('input[type="radio"][name="access_request[storefront_enabled]"]')
    assert.call("localized mode selection #{locale}", http.response.status == 200 && choices.map { |choice| choice["value"] }.sort == %w[false true] && !doc.at_css(".translation_missing"))
    assert.call("signup direction #{locale}", doc.at_css(".fx-stage")["dir"] == (locale == "ar" ? "rtl" : "ltr"))
  end
  http.post "/signup", params: { access_request: { store_name: "External workspace", email: "external-#{suffix}@example.test", storefront_enabled: "false" } }
  request = AccessRequest.find_by!(email: "external-#{suffix}@example.test")
  assert.call("signup persists external-only intent without provisioning", !request.storefront_enabled? && request.store.nil?)
  http.post "/admin/login", params: { email: root.email, password: password }
  http.get "/admin/tenants/new", params: { access_request_id: request.id }
  doc = Nokogiri::HTML(http.response.body)
  assert.call("approval preserves external-only choice", http.response.status == 200 && !doc.at_css('input[type="checkbox"][name="store[storefront_enabled]"]')["checked"])
  http.post "/admin/tenants", params: { access_request_id: request.id,
    store: { name: request.store_name, slug: "external-#{suffix}", email: request.email, currency: "MAD", storefront_enabled: "0" },
    admin: { email: request.email, password: password } }
  workspace = Store.find_by!(slug: "external-#{suffix}")
  assert.call("external workspace provisioned and request approved", http.response.redirect? && !workspace.storefront_enabled? && request.reload.store_id == workspace.id)
  assert.call("external-only provisioning skips storefront defaults", !workspace.home_sections.exists? && !workspace.menu_items.exists?)
  http.get "/admin/platform"
  overview = Nokogiri::HTML(http.response.body)
  workspace_row = overview.css("#workspaces tbody tr").find { |row| row.text.include?(workspace.name) }
  assert.call("external-only account is listed as a workspace without a public storefront link", workspace_row && workspace_row.css("a").none? { |link| link["href"] == workspace.origin })

  guest = ActionDispatch::Integration::Session.new(Rails.application)
  guest.host! "#{workspace.slug}.#{Store.base_domain}"
  %w[fr en ar].each do |locale|
    [ "/#{locale}", "/#{locale}/collections", "/#{locale}/cart", "/#{locale}/checkout" ].each do |path|
      guest.get path
      assert.call("disabled storefront blocks #{path}", guest.response.status == 404)
    end
  end
  guest.get "/admin/login"
  assert.call("external workspace login stays available", guest.response.status == 200)
  guest.get "/admin/store/edit"
  assert.call("settings require authentication", guest.response.redirect?)
  guest.post "/admin/login", params: { email: request.email, password: password }
  guest.get "/admin/store/edit"
  assert.call("external-only staff can edit settings", guest.response.status == 200 && guest.response.body.include?("store[storefront_enabled]"))
  guest.patch "/admin/store", params: { store: { storefront_enabled: "1" } }
  assert.call("staff can enable storefront and install defaults", guest.response.redirect? && workspace.reload.storefront_enabled? && workspace.home_sections.exists? && workspace.menu_items.exists?)
  section_ids = workspace.home_sections.order(:id).pluck(:id)
  %w[fr en ar].each do |locale|
    guest.get "/#{locale}"
    assert.call("enabled storefront accessible #{locale}", guest.response.status == 200)
  end
  guest.patch "/admin/store", params: { store: { storefront_enabled: "0" } }
  assert.call("disabling keeps existing content", !workspace.reload.storefront_enabled? && workspace.home_sections.order(:id).pluck(:id) == section_ids)
  guest.patch "/admin/store", params: { store: { storefront_enabled: "1" } }
  assert.call("reenabling does not duplicate content", workspace.reload.storefront_enabled? && workspace.home_sections.order(:id).pluck(:id) == section_ids)
  guest.host! "#{legacy.slug}.#{Store.base_domain}"
  guest.patch "/admin/store", params: { store: { storefront_enabled: "0" } }
  assert.call("staff cannot change another tenant", guest.response.redirect? && legacy.reload.storefront_enabled?)
  http.patch "/admin/tenants/#{workspace.id}", params: { store: { storefront_enabled: "0" } }
  assert.call("platform can disable storefront", http.response.redirect? && !workspace.reload.storefront_enabled?)
  http.get "/admin/store/edit"
  assert.call("platform-only session has no tenant settings", http.response.redirect?)
  http.patch "/admin/tenants/#{workspace.id}", params: { store: { storefront_enabled: "1" } }
  assert.call("platform can reenable storefront", http.response.redirect? && workspace.reload.storefront_enabled?)

  puts "Optional storefront: #{checks} checks passed"
  raise ActiveRecord::Rollback
end
