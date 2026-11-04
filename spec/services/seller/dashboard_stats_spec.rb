# frozen_string_literal: true

require "rails_helper"

# The dashboard keeps the order counts and rates. Money figures are AccountingStats' job (see its spec).
RSpec.describe Seller::DashboardStats do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { Store.create!(name: "Stats #{suffix}", slug: "stats-#{suffix}", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "client-#{suffix}@example.test") }
  let(:now) { Time.find_zone("Africa/Casablanca").local(2026, 11, 3, 14, 0) }
  let(:stats) { described_class.new(store: store, period: "7d", now: now).to_h }

  def order(status:, total: 10_000, at: now - 1.day, delivered_at: nil, returned_at: nil, currency: "MAD")
    store.orders.create!(customer: customer, number: "T#{SecureRandom.hex(4)}", status: status, currency: currency,
      customer_name: "Client", customer_phone: "0612345678", customer_city: "Fès", customer_address: "Rue 1",
      subtotal_cents: total, total_cents: total, created_at: at, delivered_at: delivered_at, returned_at: returned_at)
  end

  it "returns zeros and no invented activity for a new workspace" do
    expect(stats[:kpis]).to include(orders: 0, delivered: 0, delivery_rate: nil, confirmation_rate: nil)
    expect(stats[:latest]).to eq([])
    expect(stats[:currency]).to eq("MAD")
  end

  it "no longer computes any money result: that belongs to AccountingStats" do
    order(status: "delivered", total: 20_000, delivered_at: now - 1.day)
    expect(stats.keys).to match_array(%i[period currency pending kpis latest])
    expect(stats[:kpis].keys).not_to include(:revenue, :net_profit, :average_order, :revenue_delta)
  end

  it "reports how many active products have no cost" do
    store.products.create!(name: "Sans coût", slug: "sans-cout-#{suffix}", price_cents: 5_000, status: "active")
    store.products.create!(name: "Avec coût", slug: "avec-cout-#{suffix}", price_cents: 5_000, cost_cents: 2_000, status: "active")
    expect(described_class.new(store: store, now: now).missing_costs).to eq(1)
  end

  it "derives rates from the orders created in the period" do
    order(status: "new")
    order(status: "cancelled")
    order(status: "confirmed")
    order(status: "delivered", delivered_at: now - 1.day)
    order(status: "returned", returned_at: now - 1.day)
    order(status: "in_transit")

    expect(stats[:kpis]).to include(orders: 6, confirmation_rate: 67, delivery_rate: 33, cancelled: 1, cancel_rate: 17, refused: 1, refusal_rate: 50)
  end

  it "separates waiting work (all time) from the period figures" do
    order(status: "new", total: 12_000, at: now - 40.days)
    order(status: "in_transit", total: 8_000, at: now - 40.days)
    expect(stats[:kpis]).to include(orders: 0, awaiting: 1, awaiting_amount: 120.0, in_transit: 1, in_transit_amount: 80.0)
    expect(stats[:pending]).to eq(1)
  end

  it "compares the order count with the previous period" do
    2.times { order(status: "new") }
    4.times { order(status: "new", at: now - 9.days) }
    expect(stats[:kpis]).to include(orders: 2, orders_delta: -50)
  end

  it "keeps workspaces and currencies apart and treats DH as MAD" do
    other = Store.create!(name: "Other #{suffix}", slug: "other-#{suffix}", currency: "MAD")
    foreign_customer = other.customers.create!(name: "Autre", phone: "0699999999", email: "autre-#{suffix}@example.test")
    other.orders.create!(customer: foreign_customer, number: "F#{suffix}", status: "new", currency: "MAD", customer_name: "Autre", customer_phone: "0699999999",
      customer_city: "Rabat", customer_address: "Rue 2", total_cents: 99_900, created_at: now - 1.day)
    order(status: "new", currency: "DH")
    order(status: "new", currency: "EUR")
    expect(stats[:kpis][:orders]).to eq(1)
  end

  it "falls back to seven days for an unknown period" do
    expect(described_class.new(store: store, period: "nonsense", now: now).period).to eq("7d")
  end

  it "lists the six most recent orders" do
    7.times { |i| order(status: "new", at: now - i.hours) }
    expect(stats[:latest].length).to eq(6)
  end
end
