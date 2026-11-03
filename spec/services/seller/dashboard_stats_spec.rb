# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seller::DashboardStats do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { Store.create!(name: "Stats #{suffix}", slug: "stats-#{suffix}", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "client-#{suffix}@example.test") }
  let(:now) { Time.find_zone("Africa/Casablanca").local(2026, 11, 3, 14, 0) }
  let(:stats) { described_class.new(store: store, period: "7d", now: now).to_h }

  def order(status:, total: 10_000, cost: nil, fee: nil, at: now - 1.day, delivered_at: nil, returned_at: nil, product: "Montre", currency: "MAD")
    record = store.orders.create!(customer: customer, number: "T#{SecureRandom.hex(4)}", status: status, currency: currency,
      customer_name: "Client", customer_phone: "0612345678", customer_city: "Fès", customer_address: "Rue 1",
      subtotal_cents: total, total_cents: total, sendit_fee: fee, created_at: at, delivered_at: delivered_at, returned_at: returned_at)
    record.order_items.create!(product_name: product, quantity: 1, unit_price_cents: total, total_cents: total, unit_cost_cents: cost)
    record
  end

  def spend(cents, on: now.to_date)
    account = AdvertisingAccount.find_or_create_by!(store: store, provider: AdvertisingAccount::PROVIDERS.first, name: "Compte")
    campaign = account.advertising_campaigns.first || account.advertising_campaigns.create!(name: "Campagne")
    campaign.advertising_performances.create!(date: on, spend_cents: cents)
  end

  it "returns zeros and no invented activity for a new workspace" do
    expect(stats[:kpis]).to include(orders: 0, revenue: 0.0, net_profit: 0.0, delivered: 0, delivery_rate: nil, confirmation_rate: nil, average_order: nil)
    expect(stats[:series].length).to eq(7)
    expect(stats[:products]).to eq([])
    expect(stats[:latest]).to eq([])
    expect(stats[:currency]).to eq("MAD")
  end

  it "computes net profit as delivered sales minus goods, delivery fees, advertising and agent pay" do
    agent = store.users.create!(email: "agent-#{suffix}@example.test", password: "Synthetic-confirmer-#{suffix}-pw", confirmation_role: "agent", pay_per_delivery_cents: 500)
    delivered = order(status: "delivered", total: 20_000, cost: 6_000, fee: 25, delivered_at: now - 1.day)
    OrderConfirmation.create!(store: store, order: delivered, assigned_user: agent, disposition: "confirmed")
    order(status: "returned", total: 15_000, cost: 5_000, fee: 25, returned_at: now - 2.days)
    spend(2_000)

    expect(stats[:profit]).to eq(revenue: 200.0, products: 60.0, delivery: 50.0, ads: 20.0, agents: 5.0, net: 65.0)
    expect(stats[:kpis]).to include(revenue: 200.0, net_profit: 65.0, average_order: 200.0)
  end

  it "counts a product without a cost as free and reports how many are missing a cost" do
    order(status: "delivered", total: 10_000, cost: nil, delivered_at: now - 1.day)
    store.products.create!(name: "Sans coût", slug: "sans-cout-#{suffix}", price_cents: 5_000, status: "active")
    store.products.create!(name: "Avec coût", slug: "avec-cout-#{suffix}", price_cents: 5_000, cost_cents: 2_000, status: "active")
    expect(stats[:profit]).to include(revenue: 100.0, products: 0.0, net: 100.0)
    expect(stats[:missing_costs]).to eq(1)
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

  it "compares with the previous period" do
    order(status: "delivered", total: 20_000, delivered_at: now - 1.day)
    order(status: "delivered", total: 10_000, at: now - 9.days, delivered_at: now - 8.days)
    order(status: "new", at: now - 9.days)
    expect(stats[:kpis]).to include(revenue_delta: 100, orders_delta: -50)
  end

  it "keeps workspaces and currencies apart and treats DH as MAD" do
    other = Store.create!(name: "Other #{suffix}", slug: "other-#{suffix}", currency: "MAD")
    foreign_customer = other.customers.create!(name: "Autre", phone: "0699999999", email: "autre-#{suffix}@example.test")
    other.orders.create!(customer: foreign_customer, number: "F#{suffix}", status: "delivered", currency: "MAD", customer_name: "Autre", customer_phone: "0699999999",
      customer_city: "Rabat", customer_address: "Rue 2", total_cents: 99_900, delivered_at: now - 1.day)
    order(status: "delivered", total: 10_000, currency: "DH", delivered_at: now - 1.day)
    order(status: "delivered", total: 50_000, currency: "EUR", delivered_at: now - 1.day)
    expect(stats[:kpis][:revenue]).to eq(100.0)
  end

  it "ranks products by profit and keeps the worst one when it loses money" do
    %w[A B C D E].each_with_index { |name, i| order(status: "delivered", total: 10_000 + i * 1_000, cost: 1_000, product: name, delivered_at: now - 1.day) }
    order(status: "delivered", total: 1_000, cost: 5_000, product: "Perte", delivered_at: now - 1.day)
    names = stats[:products].map { |row| row[:name] }
    expect(names).to eq(%w[E D C Perte])
    expect(stats[:products].last[:profit]).to eq(-40.0)
  end

  it "builds the daily series for each period" do
    order(status: "delivered", total: 10_000, delivered_at: now - 1.day)
    spend(300, on: (now - 1.day).to_date)
    expect(stats[:series].last(2)).to eq([ { date: "2026-11-02", sales: 100.0, ads: 3.0 }, { date: "2026-11-03", sales: 0.0, ads: 0.0 } ])
    expect(described_class.new(store: store, period: "today", now: now).to_h[:series].length).to eq(7)
    expect(described_class.new(store: store, period: "30d", now: now).to_h[:series].length).to eq(30)
    expect(described_class.new(store: store, period: "nonsense", now: now).period).to eq("7d")
  end

  it "lists the six most recent orders" do
    7.times { |i| order(status: "new", at: now - i.hours) }
    expect(stats[:latest].length).to eq(6)
  end
end
