# frozen_string_literal: true

raise "Admin session smoke requires the isolated test environment" unless Rails.env.test?
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  store = Store.create!(slug: "sess-#{suffix}", name: "Session CI", currency: "MAD")
  other = Store.create!(slug: "sess-other-#{suffix}", name: "Other Session CI", currency: "MAD")
  password = SecureRandom.hex(12)
  owner = store.users.create!(email: "owner-#{suffix}@example.test", name: "Owner", password: password, admin: true)
  staff = store.users.create!(email: "staff-#{suffix}@example.test", name: "Staff", password: password, admin: true)
  foreign = other.users.create!(email: "foreign-#{suffix}@example.test", password: password, admin: true)

  browser = lambda do |host = store|
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.host! "#{host.slug}.lvh.me"
    http
  end
  login = lambda do |http, user, pass = password|
    http.post "/admin/login", params: { email: user.email, password: pass }
  end

  # Login creates a server-side session and audit record
  http = browser.call
  http.get "/admin"
  assert.call("anonymous admin redirected", http.response.redirect?)
  http.get "/admin/login"
  before_cookie = http.cookies["_morea_session"]
  login.call(http, owner)
  assert.call("login succeeds", http.response.redirect? && http.response.location.end_with?("/admin"))
  assert.call("session id rotated at login", http.cookies["_morea_session"] != before_cookie)
  admin_session = AdminSession.find_by!(user: owner)
  assert.call("session row stores digest only", admin_session.token_digest.length == 64 && admin_session.store_id == store.id)
  http.get "/admin/staff"
  assert.call("session authorizes admin", http.response.status == 200)
  assert.call("sign-in audited with actor and source", AuditEvent.exists?(action: "auth.sign_in", actor_user_id: owner.id, store_id: store.id, source: "ui"))

  # Idle expiry, absolute expiry and revocation
  admin_session.update_columns(last_seen_at: 13.hours.ago)
  http.get "/admin/staff"
  assert.call("idle session rejected", http.response.redirect? && http.response.location.include?("/admin/login"))
  admin_session.update_columns(last_seen_at: Time.current, expires_at: 1.minute.ago)
  http.get "/admin/staff"
  assert.call("expired session rejected", http.response.redirect?)
  admin_session.update_columns(expires_at: 1.day.from_now)
  http.get "/admin/staff"
  assert.call("valid session accepted again", http.response.status == 200)
  admin_session.revoke!
  http.get "/admin/staff"
  assert.call("revoked session rejected", http.response.redirect?)

  # Tenant boundary: a session minted for store A cannot be replayed on store B's host
  http = browser.call
  login.call(http, owner)
  cookie = http.cookies["_morea_session"]
  stolen = browser.call(other)
  stolen.cookies["_morea_session"] = cookie
  stolen.get "/admin/staff"
  assert.call("store A session denied on store B host", stolen.response.redirect?)
  http_other = browser.call(other)
  login.call(http_other, owner)
  assert.call("store A staff cannot sign in on store B", http_other.response.status == 422)

  # Password change revokes other sessions but keeps the current one
  mine = browser.call
  theirs = browser.call
  login.call(mine, owner)
  login.call(theirs, staff)
  mine.patch "/admin/staff/#{staff.id}", params: { user: { password: "changed-#{suffix}", password_confirmation: "changed-#{suffix}" } }
  assert.call("password update accepted", mine.response.redirect?)
  theirs.get "/admin/staff"
  assert.call("changed user's other session revoked", theirs.response.redirect?)
  mine.get "/admin/staff"
  assert.call("actor's own session survives", mine.response.status == 200)
  assert.call("password change audited", AuditEvent.exists?(action: "auth.password_changed", actor_user_id: owner.id, subject_id: staff.id))

  # Logout revokes server-side
  active_before = AdminSession.active.where(user: owner).count
  mine.delete "/admin/logout"
  assert.call("logout revokes row", AdminSession.active.where(user: owner).count == active_before - 1)
  mine.get "/admin/staff"
  assert.call("after logout redirected", mine.response.redirect?)

  # Throttling and uniform failure text, no secrets in audit
  attacker = browser.call
  10.times { login.call(attacker, foreign, "wrong") }
  login.call(attacker, foreign, "wrong")
  assert.call("repeated failures throttled", attacker.response.status == 429)
  login.call(attacker, foreign, password)
  assert.call("throttle blocks even correct password during window", attacker.response.status == 429)
  failed = AuditEvent.where(action: "auth.sign_in_failed").last
  assert.call("failure stores email digest, not email", failed.metadata["email_digest"].present? && !failed.metadata.to_s.include?("@"))

  # Token events and append-only audit
  mine = browser.call
  login.call(mine, owner)
  mine.post "/admin/agent_api/token"
  assert.call("api token generation audited", AuditEvent.exists?(action: "api_token.generated", actor_user_id: owner.id))
  mine.delete "/admin/agent_api/token"
  event = AuditEvent.find_by!(action: "api_token.revoked")
  readonly = begin
    event.update!(action: "x")
    false
  rescue ActiveRecord::ReadOnlyRecord
    true
  end
  assert.call("audit rows are read-only", readonly && event.reload.action == "api_token.revoked")
  event.destroy
  assert.call("audit rows cannot be destroyed", AuditEvent.exists?(event.id))
  redacted = AuditEvent.redact({ "phone" => "0612345678", "token" => "t", "ok" => "fine", "n" => { "password" => "p" } })
  assert.call("secrets and phone numbers redacted", redacted == { "phone" => "[FILTERED]", "token" => "[FILTERED]", "ok" => "fine", "n" => { "password" => "[FILTERED]" } })

  # Deleting staff keeps the audit trail with a label
  mine.delete "/admin/staff/#{staff.id}"
  assert.call("staff deleted", !User.exists?(staff.id))
  kept = AuditEvent.where(action: "staff.deleted", actor_user_id: owner.id).last
  assert.call("audit survives staff deletion with actor label", kept&.actor_label == "Owner")
  AuditEvent.where(action: "staff.deleted", actor_user_id: owner.id).last.then { |e| owner.destroy!; e.reload }
  assert.call("actor id nulled but label kept after actor deletion", kept.reload.actor_user_id.nil? && kept.actor_label == "Owner")

  puts "Admin session and audit checks passed: #{checks}"
  raise ActiveRecord::Rollback
end
