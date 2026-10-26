require "rails_helper"

RSpec.describe Confirmations::Desk, "handling time" do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "handling-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:agent) { store.users.create!(email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:product) { store.products.create!(slug: "tee-#{SecureRandom.hex(3)}", name: "Synthetic tee", price_cents: 10_000, stock: 10, status: "active", track_inventory: true) }
  let(:desk) { described_class.new(store: store, user: agent) }

  def new_order
    editor = Orders::Editor.new(store: store, user: agent, external_effects: false)
    order = editor.create(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca", address: "Synthetic address",
      lines: [ { product_id: product.id, quantity: 1 } ])
    raise editor.errors.full_messages.to_sentence unless order

    order
  end

  it "stores how long the agent held the order when the outcome is recorded" do
    order = new_order
    desk.claim(order.id)
    OrderConfirmation.find_by!(order: order).update!(claimed_at: 5.minutes.ago)

    desk.record(order.id, outcome: "no_answer")

    attempt = ConfirmationAttempt.find_by!(store: store, outcome: "no_answer")
    expect(attempt.handled_seconds).to be_within(5).of(300)
  end

  it "rejects a negative handling time at the database level" do
    order = new_order
    confirmation = OrderConfirmation.create!(store: store, order: order)

    expect {
      ConfirmationAttempt.new(store: store, order_confirmation: confirmation, user: agent, outcome: "no_answer", handled_seconds: -1, actor_label: "Agent").save!(validate: false)
    }.to raise_error(ActiveRecord::StatementInvalid, /confirmation_attempt_handled_nonnegative/)
  end
end
