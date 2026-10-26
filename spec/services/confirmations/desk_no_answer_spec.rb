require "rails_helper"

RSpec.describe Confirmations::Desk, "no-answer limit" do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "noanswer-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
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

  def call(order, outcome, **options)
    desk.claim(order.id)
    desk.record(order.id, outcome: outcome, **options)
  end

  it "keeps an order callable after the first and second unanswered calls" do
    order = new_order

    call(order, "no_answer")
    call(order, "no_answer")

    expect(order.reload.status).to eq("new")
    expect(OrderConfirmation.find_by!(order: order).disposition).to eq("no_answer")
    expect { desk.claim(order.id) }.not_to raise_error
  end

  it "cancels the order on the third unanswered call" do
    order = new_order

    call(order, "no_answer")
    call(order, "no_answer")
    call(order, "no_answer")

    confirmation = OrderConfirmation.find_by!(order: order)
    expect(order.reload.status).to eq("cancelled")
    expect(confirmation.disposition).to eq("cancelled")
    expect(confirmation.confirmation_attempts.where(outcome: "no_answer").count).to eq(3)
    expect(order.order_events.pluck(:body).any? { |body| body.include?(Confirmations::Desk::AUTO_CANCEL_REASON) }).to be(true)
  end

  it "counts only unanswered calls toward the limit" do
    order = new_order

    call(order, "no_answer")
    call(order, "callback", callback_at: 1.hour.from_now)
    confirmation = OrderConfirmation.find_by!(order: order)
    confirmation.update!(callback_at: 1.minute.ago)
    call(order, "no_answer")

    expect(order.reload.status).to eq("new")
    expect(confirmation.reload.disposition).to eq("no_answer")
    expect(confirmation.confirmation_attempts.count).to eq(3)
  end
end
