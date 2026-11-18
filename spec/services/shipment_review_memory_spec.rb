# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::ShipmentReview, "bounded shipment history" do
  let(:now) { Time.zone.parse("2026-11-18 12:00:00") }
  let(:store) { Store.create!(name: "Shipment history", slug: "shipment-history-#{SecureRandom.hex(4)}", currency: "MAD", sendit_public_key: "synthetic", sendit_secret_key: "synthetic") }

  def order(status:, at:, phone: "0612345678", on: store, **attributes)
    customer = on.customers.find_or_create_by!(phone: phone) { |row| row.name = "Synthetic customer" }
    row = on.orders.create!({ customer: customer, number: SecureRandom.hex(8), status: status, currency: "MAD",
      customer_name: "Synthetic customer", customer_phone: phone, customer_city: "Fes", customer_address: "Synthetic address",
      subtotal_cents: 1000, total_cents: 1000, created_at: at, skip_auto_whatsapp: true }.merge(attributes))
    row.order_items.create!(product_name: "Synthetic basket", quantity: 1, unit_price_cents: 1000, total_cents: 1000)
    row
  end

  it "aggregates cancellation counts and fallback dates without loading cancelled orders or their items" do
    candidate = order(status: "confirmed", at: now)
    order(status: "cancelled", at: now - 365.days, phone: "+212612345678", cancelled_at: now - 2.days)
    order(status: "cancelled", at: now - 1.day)
    order(status: "cancelled", at: now - 366.days, cancelled_at: now)
    order(status: "returned", at: now - 1.day)
    foreign = Store.create!(name: "Foreign", slug: "foreign-shipment-#{SecureRandom.hex(4)}", currency: "MAD")
    order(status: "cancelled", at: now, on: foreign)
    loaded_orders = 0
    loaded_items = 0
    listener = lambda do |*args|
      payload = args.last
      loaded_orders += payload[:record_count] if payload[:class_name] == "Order"
      loaded_items += payload[:record_count] if payload[:class_name] == "OrderItem"
    end
    rows = nil
    ActiveSupport::Notifications.subscribed(listener, "instantiation.active_record") do
      rows = described_class.new(store: store, now: now).rows
    end
    expect(rows.map { |row| row.order.id }).to eq([ candidate.id ])
    expect(rows.first.issues).to eq([ :prior_cancelled ])
    expect(rows.first.cancelled_count).to eq(2)
    expect(rows.first.cancelled_last_at).to eq(now - 1.day)
    # Candidate is loaded once for the page and once as a possible duplicate.
    expect(loaded_orders).to eq(2)
    expect(loaded_items).to eq(2)
  end

  it "keeps duplicate boundary checks and excludes histories beyond every candidate's window" do
    twin = order(status: "in_transit", at: now - 14.days, sendit_code: "SYNTHETIC-PARCEL")
    order(status: "delivered", at: now - 14.days - 1.second)
    order(status: "delivered", at: now + 14.days + 1.second)
    candidate = order(status: "confirmed", at: now)
    loaded = 0
    listener = ->(*args) { loaded += args.last[:record_count] if args.last[:class_name] == "Order" }
    rows = nil
    ActiveSupport::Notifications.subscribed(listener, "instantiation.active_record") do
      rows = described_class.new(store: store, now: now).rows
    end
    expect(rows.first.order).to eq(candidate)
    expect(rows.first.duplicate_of).to eq(twin)
    expect(rows.first.issues).to include(:duplicate)
    expect(loaded).to eq(3)
  end

  it "preserves the original 365-day lower bound even for old candidates" do
    order(status: "in_transit", at: now - 370.days, sendit_code: "SYNTHETIC-OLD-PARCEL")
    candidate = order(status: "confirmed", at: now - 369.days)
    row = described_class.new(store: store, now: now).rows.first
    expect(row.order).to eq(candidate)
    expect(row.duplicate_of).to be_nil
    expect(row.issues).not_to include(:duplicate)
  end
end
