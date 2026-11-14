# frozen_string_literal: true

require "rails_helper"

RSpec.describe Order, "inventory reservation on confirmation" do
  let(:store) { Store.create!(slug: "inv-#{SecureRandom.hex(4)}", name: "Inventory", currency: "MAD") }
  let(:owner) do
    store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test",
      password: "synthetic-password-123", admin: true)
  end
  let!(:tracked) do
    store.products.create!(name: "Tracked", price_cents: 10_000, status: "active", track_inventory: true, stock: 5)
  end
  let!(:untracked) do
    store.products.create!(name: "Untracked", price_cents: 4_000, status: "active", track_inventory: false, stock: 0)
  end

  def create_order(lines:)
    editor = Orders::Editor.new(store: store, user: owner, external_effects: false)
    editor.create(
      name: "Buyer",
      phone: "0612345678",
      city: "Casablanca",
      address: "Rue 1",
      lines: lines
    ) || raise(editor.errors.full_messages.to_sentence)
  end

  it "does not reserve stock while the order is still new" do
    order = create_order(lines: [ { product_id: tracked.id, quantity: 2 } ])

    expect(order.status).to eq("new")
    expect(tracked.reload.stock).to eq(5)
    expect(order.inventory_movements).to be_empty
  end

  it "reserves tracked stock on confirm and restores it on cancel" do
    order = create_order(lines: [
      { product_id: tracked.id, quantity: 2 },
      { product_id: untracked.id, quantity: 1 }
    ])

    order.transition_to!("confirmed")
    expect(order.reload.status).to eq("confirmed")
    expect(tracked.reload.stock).to eq(3)
    expect(untracked.reload.stock).to eq(0)
    expect(order.inventory_movements.where(reason: "order_confirmed").sum(:quantity)).to eq(-2)

    order.transition_to!("cancelled", reason: "Customer cancelled")
    expect(order.reload.status).to eq("cancelled")
    expect(tracked.reload.stock).to eq(5)
    expect(order.inventory_movements.where(reason: "order_cancelled").sum(:quantity)).to eq(2)
  end

  it "refuses confirmation when stock is insufficient and leaves the order new" do
    order = create_order(lines: [ { product_id: tracked.id, quantity: 2 } ])
    tracked.update!(stock: 1)

    expect {
      order.transition_to!("confirmed")
    }.to raise_error(StandardError, /Insufficient stock/)

    expect(order.reload.status).to eq("new")
    expect(tracked.reload.stock).to eq(1)
    expect(order.inventory_movements).to be_empty
  end

  it "restores reserved stock when an in-flight order is returned" do
    order = create_order(lines: [ { product_id: tracked.id, quantity: 1 } ])
    order.transition_to!("confirmed")
    order.transition_to!("preparing")
    # Carrier sync jumps past warehouse states; return is allowed once the parcel is picked up.
    order.update_columns(status: "picked_up", shipped_at: Time.current)

    order.transition_to!("returned", reason: "Refused at door")
    expect(order.reload.status).to eq("returned")
    expect(tracked.reload.stock).to eq(5)
    expect(order.inventory_movements.where(reason: "order_returned").sum(:quantity)).to eq(1)
  end
end
