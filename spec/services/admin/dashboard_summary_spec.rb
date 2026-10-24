require "rails_helper"

RSpec.describe Admin::DashboardSummary do
  let(:now) { Time.find_zone!("Africa/Casablanca").local(2026, 10, 24, 12, 30) }
  let(:store) { workspace }

  def workspace(**attributes)
    Store.create!({ slug: "summary-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD" }.merge(attributes))
  end

  def order(workspace: store, cents: 101, at: now, **attributes)
    customer = workspace.customers.first || workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!({ customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: cents,
      subtotal_cents: cents, currency: "MAD", status: "new", created_at: at, updated_at: at }.merge(attributes))
  end

  def connection(workspace: store, **attributes)
    workspace.store_connections.create!({ provider: "woocommerce", name: "Synthetic source",
      external_domain: "source-#{SecureRandom.hex(5)}.example.test", webhook_secret: "synthetic-signing-secret" }.merge(attributes))
  end

  def summary(**attributes)
    described_class.new(store: store, now: now, **attributes)
  end

  it "requires a persisted workspace rather than querying without a tenant" do
    [ nil, Store.new, Object.new ].each do |invalid|
      expect { described_class.new(store: invalid) }.to raise_error(ArgumentError, /workspace/)
    end
  end

  it "distinguishes storefront, external-only and combined workspaces" do
    expect(summary.mode).to eq("storefront")
    connection
    expect(summary.mode).to eq("combined")
    store.update!(storefront_enabled: false)
    expect(summary.mode).to eq("connected")
    expect(summary.active_carts_count).to eq(0)
  end

  it "uses inclusive Casablanca calendar boundaries with the exact current-time upper bound" do
    boundary = Time.find_zone!("Africa/Casablanca").local(2026, 10, 18)
    order(at: boundary - 1.second, cents: 999)
    order(at: boundary, cents: 123)
    order(at: now, cents: 456, archived_at: now)
    order(at: now + 1.second, cents: 888)
    order(workspace: workspace, cents: 777)

    result = summary
    expect(result.starts_at).to eq(boundary)
    expect(result.ends_at).to eq(now)
    expect(result.orders_count).to eq(2)
    expect(result.order_values).to eq("MAD" => 579)
  end

  it "supports a 30-day cohort and safely defaults invalid periods to seven days" do
    order(at: now.beginning_of_day - 29.days, cents: 123)
    order(at: now.beginning_of_day - 29.days - 1.second, cents: 999)
    expect(summary(period: "30").orders_count).to eq(1)
    expect(summary(period: "30").starts_at).to eq(now.beginning_of_day - 29.days)
    expect(summary(period: "bogus").days).to eq(7)
    expect(summary(period: nil).orders_count).to eq(0)
  end

  it "keeps integer cents and separate currencies while normalizing DH to MAD" do
    order(cents: 12_345, currency: "MAD", status: "delivered")
    order(cents: 123, currency: "DH", status: "cancelled")
    order(cents: 777, currency: "EUR")
    result = summary
    expect(result.order_values).to eq("MAD" => 12_468, "EUR" => 777)
    expect(result.order_value_cents).to eq(12_468)
    expect([ result.delivered_count, result.cancelled_count ]).to eq([ 1, 1 ])
  end

  it "counts active work across all time while excluding archived, terminal and carrier callbacks" do
    due = order(at: now - 45.days)
    due.create_order_confirmation!(store: store, disposition: "callback", callback_at: now)
    future = order(at: now - 45.days)
    future.create_order_confirmation!(store: store, disposition: "callback", callback_at: now + 1.second)
    [ order(archived_at: now), order(status: "delivered"), order(sendit_code: "synthetic-parcel") ].each do |excluded|
      excluded.create_order_confirmation!(store: store, disposition: "callback", callback_at: now - 1.hour)
    end
    Order::PROBLEM_STATUSES.each { |status| order(at: now - 45.days, status: status) }
    order(status: "address_issue", archived_at: now)
    order(workspace: workspace, status: "address_issue")
    expect(summary.pending_count).to eq(2)
    expect(summary.callbacks_due_count).to eq(1)
    expect(summary.delivery_issues_count).to eq(3)
  end

  it "prioritizes errors, awaiting verification, verified and disconnected sources with a bounded list" do
    disconnected = connection(active: false, verified_at: now)
    verified = connection(verified_at: now)
    awaiting = connection
    error = connection(last_error_code: "incomplete_payload")
    5.times { connection(active: false) }
    connection(workspace: workspace, last_error_code: "foreign-error")

    result = summary
    expect(result.connections_count).to eq(9)
    expect(result.connections.size).to eq(6)
    expect(result.connections.first(3).map(&:id)).to eq([ error.id, awaiting.id, verified.id ])
    expect(result.connections.drop(3)).to all(have_attributes(active: false))
    expect(awaiting.connection_state).to eq("configured")
    expect(disconnected.connection_state).to eq("disconnected")
  end

  it "aggregates source receipts within the selected period and tenant without mixing currencies" do
    source = connection
    [ [ "MAD", 123 ], [ "DH", 2 ], [ "EUR", 456 ] ].each_with_index do |(currency, cents), index|
      source.external_order_receipts.create!(external_id: "accepted-#{index}", status: "accepted",
        order: order(cents: cents, currency: currency), received_at: now)
    end
    source.external_order_receipts.create!(external_id: "rejected", status: "rejected", error_code: "incomplete_payload", received_at: now)
    source.external_order_receipts.create!(external_id: "old-rejected", status: "rejected", error_code: "incomplete_payload", received_at: now - 45.days)
    foreign_source = connection(workspace: workspace)
    foreign_source.external_order_receipts.create!(external_id: "foreign", status: "rejected", error_code: "incomplete_payload", received_at: now)

    expect(summary.rejected_count).to eq(2)
    expect(summary.source_stats.fetch(source.id)).to eq(orders_count: 3, order_value_cents: 125,
      order_values: { "MAD" => 125, "EUR" => 456 }, rejected_count: 1)
  end

  it "bounds recent orders and omits archived, future and foreign records" do
    10.times { |index| order(at: now - index.minutes) }
    order(archived_at: now)
    order(at: now + 1.second)
    order(workspace: workspace)
    recent = summary.recent_orders
    expect(recent.size).to eq(8)
    expect(recent).to all(have_attributes(store_id: store.id, archived_at: nil))
    expect(recent.map(&:created_at)).to eq(8.times.map { |index| now - index.minutes })
  end
end
