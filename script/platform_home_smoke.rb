# frozen_string_literal: true

raise "Platform home smoke requires the isolated test environment" unless Rails.env.test?
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  store = Store.create!(slug: "home-#{suffix}", name: "Home CI", currency: "MAD")
  apex = ActionDispatch::Integration::Session.new(Rails.application)
  apex.host! Store.base_domain

  apex.get "/"
  assert.call("apex root renders the platform page without redirect", apex.response.status == 200 && apex.response.body.include?(Store.platform_name))
  assert.call("platform page links to admin sign-in", apex.response.body.include?('href="/admin/login"'))
  assert.call("platform page does not list tenants", !apex.response.body.include?(store.name))
  Morea::Locales::AVAILABLE.each do |locale|
    apex.get "/", params: { locale: locale }
    assert.call("#{locale} renders", apex.response.status == 200 && apex.response.body.include?(%(lang="#{locale}")))
    assert.call("#{locale} direction", apex.response.body.include?(%(dir="#{locale == :ar ? "rtl" : "ltr"}")))
  end
  { "en-US,en;q=0.9" => "English", "ar" => "Arabic" }.each do |header, name|
    fresh = ActionDispatch::Integration::Session.new(Rails.application)
    fresh.host! Store.base_domain
    fresh.get "/", headers: { "Accept-Language" => header }
    assert.call("French is the default for a first visit with an #{name} browser", fresh.response.body.include?('lang="fr"'))
    fresh.get "/", params: { locale: "en" }
    assert.call("explicit locale still wins", fresh.response.body.include?('lang="en"'))
  end
  apex.get "/fr"
  assert.call("apex never redirects to a store", apex.response.status == 404 && apex.response.location.blank?)
  apex.get "/fr/products/anything"
  assert.call("apex product paths are not found", apex.response.status == 404)
  apex.get "/admin/login"
  assert.call("apex admin login unchanged", apex.response.status == 200)

  tenant = ActionDispatch::Integration::Session.new(Rails.application)
  tenant.host! "#{store.slug}.#{Store.base_domain}"
  tenant.get "/"
  assert.call("tenant root still redirects to its localized storefront", tenant.response.redirect? && tenant.response.location =~ %r{/(fr|en|ar)\z})
  assert.call("tenant root is not the platform page", !tenant.response.body.include?(Store.platform_name))

  local = ActionDispatch::Integration::Session.new(Rails.application)
  local.host! "localhost"
  local.get "/"
  assert.call("localhost is the platform page, not a store", local.response.status == 200 && local.response.body.include?(Store.platform_name))
  local.host! "#{store.slug}.localhost"
  local.get "/"
  assert.call("slug.localhost opens that store", local.response.redirect? && local.response.location =~ %r{/(fr|en|ar)\z})
  local.get "/fr"
  assert.call("slug.localhost serves the storefront", local.response.status == 200 && local.response.body.include?("Home CI"))
  local.host! "missing-#{suffix}.localhost"
  local.get "/fr"
  assert.call("unknown subdomain is not found", local.response.status == 404)

  puts "Platform home checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
