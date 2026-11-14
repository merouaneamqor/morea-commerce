# frozen_string_literal: true

require "rails_helper"

RSpec.describe Confirmations::ClaimExpiry do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "exp-#{SecureRandom.hex(4)}", name: "Expiry", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) do
    store.users.create!(name: "Agent", email: "agent-#{SecureRandom.hex(4)}@example.test",
      password: password, confirmation_role: "agent")
  end
  let!(:product) { store.products.create!(name: "Item", price_cents: 5_000, status: "active") }

  def make_order
    Orders::Editor.new(store: store, user: owner, external_effects: false).create(
      name: "Buyer", phone: "0612345678", city: "Casablanca", address: "Rue 1",
      lines: [ { product_id: product.id, quantity: 1 } ]
    ) || raise("order create failed")
  end

  def claim!(order, user: agent, at: Time.current)
    confirmation = order.order_confirmation || order.create_order_confirmation!(store: store)
    confirmation.update!(assigned_user: user, claimed_at: at, last_activity_at: at)
    confirmation
  end

  it "keeps a claim inside the idle window and releases after 15 minutes" do
    order = make_order
    travel_to(Time.zone.local(2026, 11, 5, 10, 0)) do
      claim!(order)

      travel 14.minutes
      described_class.release_idle!(store)
      expect(order.reload.order_confirmation.assigned_user_id).to eq(agent.id)

      travel 2.minutes
      described_class.release_idle!(store)
      expect(order.reload.order_confirmation.assigned_user_id).to be_nil
      expect(order.order_events.pluck(:body)).to include(
        "Claim released automatically after 15 minutes without activity"
      )
    end
  end

  it "release_for! clears every claim held by the agent" do
    first = make_order
    second = make_order
    claim!(first)
    claim!(second)

    described_class.release_for!(store: store, user: agent)

    expect(first.reload.order_confirmation.assigned_user_id).to be_nil
    expect(second.reload.order_confirmation.assigned_user_id).to be_nil
    expect(first.order_events.pluck(:body)).to include(
      "Claim released: the agent clocked out"
    )
  end

  it "is a no-op when the claim is already unassigned" do
    order = make_order
    confirmation = order.create_order_confirmation!(store: store)

    expect {
      described_class.release!(confirmation, "already free")
    }.not_to change { order.order_events.count }
    expect(confirmation.reload.assigned_user_id).to be_nil
  end
end
