require "rails_helper"

RSpec.describe Admin::DeliverySummary do
  let(:now) { Time.find_zone!("Africa/Casablanca").local(2026, 10, 25, 12) }
  let(:store) { workspace }

  def workspace
    Store.create!(slug: "delivery-#{SecureRandom.hex(5)}", name: "Synthetic workspace")
  end

  def shipment(workspace: store, **attributes)
    customer = workspace.customers.first || workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!({ customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 12345,
      subtotal_cents: 12345, currency: "MAD", status: "in_transit", created_at: now }.merge(attributes))
  end

  def summary(**attributes)
    described_class.new(store: store, now: now, **attributes)
  end

  it "requires a persisted authorized workspace" do
    [nil, Store.new].each do |invalid|
      expect { described_class.new(store: invalid) }.to raise_error(ArgumentError)
    end
  end

  it "keeps tenant and date boundaries and excludes orders without a shipment" do
    own = shipment(created_at: now.beginning_of_day - 29.days)
    shipment(created_at: now.beginning_of_day - 29.days - 1.second)
    shipment(created_at: now + 1.second)
    shipment(workspace: workspace)
    shipment(status: "new")
    shipment(status: "new", sendit_code: "SYNTHETIC-NEW-PARCEL")
    shipment(status: "confirmed")
    shipment(status: "cancelled")
    expect(summary.total).to eq(1)
    expect(summary.recent_orders).to eq([own])
  end

  it "accounts for every shipment state including courier cancellations and delivery issues" do
    shipment(status: "confirmed", sendit_code: "SYNTHETIC-1")
    shipment(status: "awaiting_pickup")
    shipment(status: "in_transit")
    shipment(status: "delivered", archived_at: now)
    shipment(status: "returned")
    shipment(status: "cancelled", sendit_code: "SYNTHETIC-2")
    Order::PROBLEM_STATUSES.each { |status| shipment(status: status) }
    result = summary
    expect(result.counts).to eq("collection" => 2, "in_delivery" => 1, "delivered" => 1, "returned" => 1, "cancelled" => 1, "issues" => 3)
    expect(result.total).to eq(9)
  end

  it "filters only the bounded listing, without altering metrics or interpreting search wildcards" do
    wanted = shipment(customer_name: "Synthetic 100%", status: "returned")
    shipment(customer_name: "Synthetic 1000", status: "returned")
    shipment(customer_name: "Synthetic 100%", status: "in_transit")
    result = summary(status: "returned", query: "100%")
    expect(result.total).to eq(3)
    expect(result.recent_orders).to eq([wanted])
    31.times { shipment }
    expect(summary.recent_orders.length).to eq(30)
  end

  it "calculates durations only from delivered records with valid timestamps" do
    shipment(status: "delivered", shipped_at: now - 3.days, delivered_at: now, sendit_code: "SYNTHETIC-1")
    shipment(status: "delivered", shipped_at: now, delivered_at: now - 1.day)
    shipment(status: "delivered", shipped_at: nil, delivered_at: now)
    shipment(status: "in_transit", shipped_at: now - 8.days, delivered_at: now)
    result = summary
    expect(result.average_days).to eq(3.0)
    expect(result.couriers.first).to include(name: "Sendit", total: 1, delivered: 1, rate: 100.0, average_days: 3.0)
  end

  it "normalizes invalid, future, reversed and overly broad periods" do
    expect(summary(start_date: "bad", end_date: "bad").start_date).to eq(now.to_date - 29)
    expect(summary(end_date: "2030-01-01").end_date).to eq(now.to_date)
    expect(summary(start_date: "2030-01-01").start_date).to eq(now.to_date - 29)
    expect(summary(start_date: "2020-01-01").start_date).to eq(now.to_date - 365)
    expect(summary.percentage("delivered")).to eq(0)
    expect(summary.average_days).to be_nil
  end
end
