# frozen_string_literal: true

raise "Confirmation smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test

suffix = SecureRandom.hex(4)
store = Store.create!(slug: "confirm-#{suffix}", name: "Confirmation CI", currency: "MAD")
other = Store.create!(slug: "foreign-confirm-#{suffix}", name: "Other CI", currency: "MAD")
password = SecureRandom.hex(16)
agent = store.users.create!(email: "first@example.test", password: password, admin: true)
second = store.users.create!(email: "second@example.test", password: password, admin: true)
foreign = other.users.create!(email: "other@example.test", password: password, admin: true)
product = store.products.create!(slug: "confirm-product", name: "Confirmation item", price_cents: 10_000, stock: 10, status: "active", track_inventory: true)
checks = 0
assert = lambda { |message, value| raise message unless value; checks += 1 }
reject = lambda do |message, &block|
  rejected = false
  begin
    block.call
  rescue Confirmations::Desk::Error, ActiveRecord::RecordNotFound
    rejected = true
  end
  assert.call(message, rejected)
end
make_order = lambda do |quantity = 2|
  editor = Orders::Editor.new(store: store, user: agent, external_effects: false)
  order = editor.create(name: "CI customer", phone: "0612345678", city: "Casablanca", address: "CI address",
    lines: [ { product_id: product.id, quantity: quantity } ])
  raise editor.errors.full_messages.to_sentence unless order
  order
end
desk = Confirmations::Desk.new(store: store, user: agent)
second_desk = Confirmations::Desk.new(store: store, user: second)

begin
  order = make_order.call
  reject.call("other-store agent denied") { Confirmations::Desk.new(store: store, user: foreign).claim(order.id) }
  reject.call("other-store order lookup denied") { Confirmations::Desk.new(store: other, user: foreign).claim(order.id) }
  assert.call("no allocation from unauthorized claims", OrderConfirmation.where(order: order).count.zero?)
  desk.claim(order.id)
  desk.claim(order.id)
  assert.call("claim replay is harmless", OrderConfirmation.where(order: order).count == 1)
  reject.call("second agent cannot steal") { second_desk.claim(order.id) }
  reject.call("second agent cannot release") { second_desk.release(order.id) }
  reject.call("second agent cannot record") { second_desk.record(order.id, outcome: "confirmed") }
  reject.call("invalid outcome rejected") { desk.record(order.id, outcome: "delivered") }
  reject.call("past callback rejected") { desk.record(order.id, outcome: "callback", callback_at: 1.hour.ago) }
  assert.call("validation keeps claim", OrderConfirmation.find_by!(order: order).assigned_user_id == agent.id)
  desk.record(order.id, outcome: "callback", callback_at: 1.hour.from_now, notes: "Call later")
  assert.call("callback leaves shipping and inventory alone", order.reload.status == "new" && product.reload.stock == 10)
  reject.call("future callback not claimable") { desk.claim(order.id) }
  confirmation = OrderConfirmation.find_by!(order: order)
  confirmation.update!(callback_at: 1.minute.ago)
  desk.claim(order.id)
  desk.record(order.id, outcome: "no_answer", notes: "No response")
  assert.call("attempt history retained", confirmation.confirmation_attempts.count == 2)
  desk.claim(order.id)
  desk.release(order.id)
  assert.call("released claim empty", confirmation.reload.assigned_user_id.nil?)

  # A configured carrier would normally dispatch on confirmation. This desk must
  # use the state/stock path without any carrier calls or Sendit job enqueue.
  store.update!(sendit_public_key: "ci-public", sendit_secret_key: "ci-secret")
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  desk.claim(order.id)
  original_sync_new = Sendit::Sync.method(:new)
  Sendit::Sync.define_singleton_method(:new) { |*| raise "Confirmation attempted a carrier call" }
  begin
    desk.record(order.id, outcome: "confirmed", notes: "Customer agreed")
  ensure
    Sendit::Sync.define_singleton_method(:new, original_sync_new)
  end
  assert.call("confirmation reserves existing stock", order.reload.status == "confirmed" && product.reload.stock == 8)
  assert.call("confirmation does not enqueue carrier dispatch", ActiveJob::Base.queue_adapter.enqueued_jobs.none? { |job| job[:job] == SenditSyncJob })
  assert.call("disposition separate from shipping", confirmation.reload.disposition == "confirmed")
  reject.call("confirmed order cannot re-enter queue") { desk.claim(order.id) }
  assert.call("confirmed cannot reserve twice", product.reload.stock == 8)

  shortage = make_order.call(9)
  desk.claim(shortage.id)
  before = ConfirmationAttempt.count
  reject.call("insufficient stock reported") { desk.record(shortage.id, outcome: "confirmed") }
  assert.call("failed transition rolled back", shortage.reload.status == "new" && product.reload.stock == 8)
  assert.call("failed attempt not committed", ConfirmationAttempt.count == before)
  assert.call("failed transition keeps claim", OrderConfirmation.find_by!(order: shortage).assigned_user_id == agent.id)
  desk.record(shortage.id, outcome: "cancelled", notes: "Not available")
  assert.call("cancel new order doesn't restore unreserved stock", shortage.reload.status == "cancelled" && product.reload.stock == 8)

  race = make_order.call(1)
  gate = Queue.new
  results = Queue.new
  threads = [ agent, second ].map do |person|
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        gate.pop
        begin
          Confirmations::Desk.new(store: Store.find(store.id), user: User.find(person.id)).claim(race.id)
          results << :won
        rescue Confirmations::Desk::Error
          results << :denied
        end
      end
    end
  end
  2.times { gate << true }
  threads.each(&:join)
  assert.call("concurrent claim has one owner", [ results.pop, results.pop ].sort == %i[denied won])
  assert.call("concurrent claim keeps single row", OrderConfirmation.where(order: race).count == 1)

  retired = store.users.create!(email: "retired@example.test", password: password, admin: true)
  retired_desk = Confirmations::Desk.new(store: store, user: retired)
  audited = make_order.call(1)
  retired_desk.claim(audited.id)
  retired_desk.record(audited.id, outcome: "no_answer")
  attempt = ConfirmationAttempt.joins(:order_confirmation).find_by!(order_confirmations: { order_id: audited.id })
  actor_label = attempt.actor_label
  retired.destroy!
  assert.call("deleting staff keeps audit actor snapshot", attempt.reload.user_id.nil? && attempt.actor_label == actor_label)

  # Render the actual admin queue, including claimed controls and translated text.
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{store.slug}.lvh.me"
  http.post "/admin/login", params: { email: agent.email, password: password }
  http.get "/admin/confirmations", params: { filter: "all" }
  assert.call("queue renders", http.response.status == 200 && http.response.body.include?(race.number))
  http.get "/admin/confirmations", params: { filter: "all" }, headers: { "Accept-Language" => "ar" }
  assert.call("queue remains available with Arabic request", http.response.status == 200)
  http.host! "#{other.slug}.lvh.me"
  http.post "/admin/login", params: { email: foreign.email, password: password }
  http.get "/admin/confirmations", params: { filter: "all" }
  assert.call("foreign queue hides order", http.response.status == 200 && !http.response.body.include?(race.number))

  puts "Confirmation queue: #{checks} checks passed"
ensure
  # Order associations remove confirmations/attempts before their audit users.
  store.orders.destroy_all
  other.orders.destroy_all
  store.destroy!
  other.destroy!
end
