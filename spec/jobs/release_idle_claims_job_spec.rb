# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReleaseIdleClaimsJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "job-#{SecureRandom.hex(4)}", name: "Job Store", currency: "MAD") }
  let(:other) { Store.create!(slug: "job-o-#{SecureRandom.hex(4)}", name: "Other Job", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) do
    store.users.create!(name: "Agent", email: "agent-#{SecureRandom.hex(4)}@example.test",
      password: password, confirmation_role: "agent")
  end
  let!(:product) { store.products.create!(name: "Item", price_cents: 5_000, status: "active") }

  def make_claimed_order(workspace: store, at: Time.current)
    editor = Orders::Editor.new(store: workspace, user: owner, external_effects: false)
    order = editor.create(
      name: "Buyer", phone: "0612345678", city: "Casablanca", address: "Rue 1",
      lines: [ { product_id: product.id, quantity: 1 } ]
    ) || raise("create failed")
    confirmation = order.order_confirmation || order.create_order_confirmation!(store: workspace)
    confirmation.update!(assigned_user: agent, claimed_at: at, last_activity_at: at)
    order
  end

  it "releases idle claims and leaves fresh claims alone" do
    travel_to(Time.zone.local(2026, 11, 5, 10, 0)) do
      idle = make_claimed_order(at: 20.minutes.ago)
      fresh = make_claimed_order(at: Time.current)

      described_class.perform_now

      expect(idle.reload.order_confirmation.assigned_user_id).to be_nil
      expect(fresh.reload.order_confirmation.assigned_user_id).to eq(agent.id)
    end
  end

  it "skips stores that have no assigned claims" do
    other_owner = other.users.create!(name: "O", email: "o-#{SecureRandom.hex(4)}@example.test",
      password: password, admin: true)
    other_product = other.products.create!(name: "X", price_cents: 1_000, status: "active")
    Orders::Editor.new(store: other, user: other_owner, external_effects: false).create(
      name: "Buyer", phone: "0612345678", city: "Rabat", address: "Ave",
      lines: [ { product_id: other_product.id, quantity: 1 } ]
    )

    expect { described_class.perform_now }.not_to raise_error
  end
end
