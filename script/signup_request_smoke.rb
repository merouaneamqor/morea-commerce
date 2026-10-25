# frozen_string_literal: true

raise "Signup smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(6)
  password = "Synthetic-signup-#{suffix}"
  email = "signup-#{suffix}@example.test"
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! Store.base_domain
  %w[fr en ar].each do |locale|
    http.get "/signup", params: { locale: locale }
    assert.call("localized signup renders #{locale}", http.response.status == 200 && http.response.body.include?("registration[email]") && http.response.body.include?(%(lang="#{locale}")))
  end
  store_count, user_count, request_count = Store.count, User.count, AccessRequest.count
  http.post "/signup", params: { locale: "en", registration: {
    business_name: "Synthetic Workspace #{suffix}", email: email
  } }
  assert.call("signup redirects to email instructions", http.response.redirect? && http.response.location.include?("/signup/thanks"))
  registration = Registration.find_by!(email: email)
  assert.call("signup awaits verification without provisioning or approval", Store.count == store_count && User.count == user_count && AccessRequest.count == request_count && !registration.verified?)
  token = registration.verification_token
  http.get "/signup/verify", params: { token: token }
  assert.call("email scanners cannot activate accounts", http.response.status == 200 && !registration.reload.verified? && Store.count == store_count)
  http.post "/signup/confirm", params: { token: token, password: password, password_confirmation: password }
  assert.call("confirmation activates exactly one account", http.response.redirect? && registration.reload.verified? && Store.count == store_count + 1 && User.count == user_count + 1)
  owner = registration.user
  assert.call("account preserves password and starts unpublished", owner.authenticate(password) && !owner.store.storefront_enabled? && owner.store.subscription_required?)
  http.get "/admin"
  assert.call("verified user reaches overview", http.response.status == 200)
  http.get "/admin/products"
  assert.call("operations require subscription", http.response.redirect? && http.response.location.include?("/admin/subscription"))
  http.post "/signup/confirm", params: { token: token, password: password, password_confirmation: password }
  assert.call("confirmation token is single-use", http.response.status == 422 && Store.count == store_count + 1)
  puts "Self-service signup checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
