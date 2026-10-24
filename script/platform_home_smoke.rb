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
  assert.call("apex root renders the platform page without redirect", apex.response.status == 200 && apex.response.body.include?("Morea Commerce"))
  assert.call("platform page links to admin sign-in", apex.response.body.include?('href="/admin/login"'))
  assert.call("platform page does not list tenants", !apex.response.body.include?(store.name))
  Morea::Locales::AVAILABLE.each do |locale|
    apex.get "/", params: { locale: locale }
    assert.call("#{locale} renders", apex.response.status == 200 && apex.response.body.include?(%(lang="#{locale}")))
    assert.call("#{locale} direction", apex.response.body.include?(%(dir="#{locale == :ar ? "rtl" : "ltr"}")))
  end
  apex.get "/fr"
  assert.call("apex storefront paths still go to the default store or 404", apex.response.status.in?([ 301, 404 ]))
  apex.get "/admin/login"
  assert.call("apex admin login unchanged", apex.response.status == 200)

  tenant = ActionDispatch::Integration::Session.new(Rails.application)
  tenant.host! "#{store.slug}.#{Store.base_domain}"
  tenant.get "/"
  assert.call("tenant root still redirects to its localized storefront", tenant.response.redirect? && tenant.response.location =~ %r{/(fr|en|ar)\z})
  assert.call("tenant root is not the platform page", !tenant.response.body.include?("Morea Commerce"))

  puts "Platform home checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
