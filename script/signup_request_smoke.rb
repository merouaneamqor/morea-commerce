# frozen_string_literal: true

raise "Signup smoke requires the isolated test environment" unless Rails.env.test?
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(6)
  password = "Synthetic-signup-#{suffix}"
  email = "owner-#{suffix}@example.test"
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! Store.base_domain
  %w[fr en ar].each do |locale|
    http.get "/signup", params: { locale: locale }
    assert.call("localized signup renders #{locale}", http.response.status == 200 && http.response.body.include?("signup[email]") && http.response.body.include?(%(lang="#{locale}")))
    http.get "/abonnement", params: { locale: locale }
    assert.call("localized plans render #{locale}", http.response.status == 200 && http.response.body.include?("data-plans"))
  end
  store_count, user_count = Store.count, User.count
  http.post "/abonnement", params: { plan: "starter", billing: "monthly", currency: "USD" }
  assert.call("a guest plan choice continues to account creation", http.response.redirect? && http.response.location.include?("/signup"))
  http.post "/signup", params: { locale: "en", signup: {
    name: "Synthetic Owner", store_name: "Synthetic Workspace #{suffix}", phone: "0612345678", email: email,
    password: password, password_confirmation: password, currency: "USD"
  } }
  assert.call("signup creates the workspace and continues to payment", http.response.redirect? && http.response.location.include?("/paiement") && Store.count == store_count + 1 && User.count == user_count + 1)
  owner = User.find_by!(email: email)
  assert.call("account preserves the password, starts unpublished and on a trial", owner.authenticate(password) && !owner.store.storefront_enabled? && owner.store.trial_active?)
  http.get "/paiement"
  assert.call("payment step shows the transfer details", http.response.status == 200 && http.response.body.include?(Plans.bank["rib"]))
  http.post "/paiement/virement", params: { reference: "SMOKE-#{suffix}" }
  assert.call("a transfer is recorded as pending", owner.store.payments.pending.count == 1)
  http.get "/admin"
  assert.call("owner reaches overview", http.response.status == 200)
  http.get "/admin/products"
  assert.call("operations are open during the trial", http.response.status == 200)
  owner.store.update!(trial_ends_at: 1.day.ago)
  http.get "/admin/products"
  assert.call("operations require a subscription once the trial ends", http.response.redirect? && http.response.location.include?("/admin/subscription"))
  puts "Self-service signup checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
