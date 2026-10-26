require "rails_helper"

RSpec.describe Admin::OverviewMetrics do
  let(:now) { Time.find_zone!("Africa/Casablanca").local(2026, 10, 25, 12) }
  let(:store) { workspace }

  def workspace
    Store.create!(slug: "overview-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD")
  end

  def order(workspace: store, **attributes)
    customer = workspace.customers.first || workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!({ customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 101,
      subtotal_cents: 101, currency: "MAD", status: "new", created_at: now }.merge(attributes))
  end

  def metrics(**attributes)
    described_class.new(store: store, now: now, **attributes)
  end

  it "requires a persisted tenant and returns honest empty values" do
    [ nil, Store.new ].each { |value| expect { described_class.new(store: value) }.to raise_error(ArgumentError) }
    expect(metrics.orders_count).to eq(0)
    expect(metrics.confirmation_rate).to eq(0.0)
    expect(metrics.delivery_rate).to eq(0.0)
    expect(metrics.cancellation_rate).to eq(0.0)
    expect(metrics.average_order_values).to eq({})
    expect(metrics.delivery_success_rate).to be_nil
    expect(metrics.net_collected_values).to eq({})
    expect(metrics.net_profit_values).to eq({})
    expect(metrics.momentum_score).to eq(0)
    expect(metrics.level_key).to eq(:starter)
    expect(metrics.average_gain_per_sale).to be_nil
    expect(metrics.delivered_values).to eq({})
    expect(metrics.ad_reporting_present).to be(false)
    expect(metrics.daily_values.length).to eq(7)
    expect(metrics.daily_values.all? { |day| day[:values].empty? }).to be(true)
  end

  it "scopes current and comparable previous periods to Casablanca and the authorized tenant" do
    start = now.beginning_of_day - 6.days
    order(created_at: start, status: "confirmed")
    order(created_at: now, status: "delivered", total_cents: 12345)
    order(created_at: now + 1.second)
    order(workspace: workspace, status: "delivered", total_cents: 99999)
    order(created_at: start - 7.days, status: "delivered", total_cents: 501)
    order(created_at: now - 7.days + 1.second, status: "delivered", total_cents: 777)
    result = metrics
    expect(result.starts_at).to eq(start)
    expect(result.orders_count).to eq(2)
    expect(result.confirmation_rate).to eq(100.0)
    expect(result.delivery_rate).to eq(50.0)
    expect(result.delivery_success_rate).to eq(100.0)
    expect(result.cancellation_rate).to eq(0.0)
    expect(result.average_order_values).to eq("MAD" => 6223)
    expect(result.data_quality).to include(net_collected_revenue: :missing, net_profit: :missing,
      real_orders: :estimated, delivery_success: :verified, confirmation_rate: :estimated,
      average_order_value: :verified)
    expect(result.momentum_score).to eq(78)
    expect(result.level_key).to eq(:momentum)
    expect(result.next_level_key).to eq(:champion)
    expect(result.previous_orders_count).to eq(1)
    expect(result.previous_delivery_rate).to eq(100.0)
    expect(result.previous_delivered_values).to eq("MAD" => 501)
    expect(result.delivered_values).to eq("MAD" => 12345)
  end

  it "keeps cents and currency separate and fills zero-activity dates" do
    order(status: "delivered", total_cents: 12345, currency: "MAD")
    order(status: "delivered", total_cents: 123, currency: "DH")
    order(status: "delivered", total_cents: 777, currency: "EUR")
    order(status: "cancelled", total_cents: 10)
    result = metrics
    expect(result.delivered_values).to eq("MAD" => 12468, "EUR" => 777)
    expect(result.confirmed_count).to eq(3)
    expect(result.confirmation_rate).to eq(75.0)
    expect(result.status_counts).to eq("delivered" => 3, "cancelled" => 1)
    expect(result.daily_values.last).to eq(date: now.to_date, values: { "MAD" => 12478, "EUR" => 777 }, delivered_values: { "MAD" => 12468, "EUR" => 777 })
    expect(result.daily_values.first[:values]).to eq({})
  end

  it "ranks delivered products for this tenant without mixing currencies" do
    product = store.products.create!(name: "Top synthetic product", slug: "top-synthetic", status: "active", price_cents: 500)
    delivered = order(status: "delivered", total_cents: 1_500)
    delivered.order_items.create!(product: product, product_name: product.name, quantity: 3,
      unit_price_cents: 500, total_cents: 1_500)
    euro = order(status: "delivered", total_cents: 700, currency: "EUR")
    euro.order_items.create!(product: product, product_name: product.name, quantity: 1,
      unit_price_cents: 700, total_cents: 700)
    foreign_store = workspace
    foreign_product = foreign_store.products.create!(name: "Foreign product", slug: "foreign-product", status: "active", price_cents: 9_999)
    foreign_order = order(workspace: foreign_store, status: "delivered", total_cents: 9_999)
    foreign_order.order_items.create!(product: foreign_product, product_name: foreign_product.name, quantity: 99,
      unit_price_cents: 101, total_cents: 9_999)

    row = metrics.top_products.sole
    expect(row).to include(product: product, name: product.name, units: 4)
    expect(row[:revenue_values]).to eq("MAD" => 1_500, "EUR" => 700)
  end

  it "loads bounded active confirmation work across periods with assignment and line items" do
    old = order(created_at: now - 90.days)
    old.create_order_confirmation!(store: store, disposition: "pending")
    5.times { order }
    order(archived_at: now)
    order(status: "delivered")
    order(sendit_code: "SYNTHETIC-CARRIER")
    order(created_at: now + 1.second)
    order(workspace: workspace)
    result = metrics
    expect(result.pending_orders.length).to eq(5)
    expect(result.pending_orders.first).to eq(old)
    expect(result.pending_orders.first.association(:order_confirmation)).to be_loaded
    expect(result.pending_orders.first.association(:order_items)).to be_loaded
    expect(result.pending_orders.all? { |record| record.store_id == store.id && record.status == "new" && record.archived_at.nil? && record.sendit_code.blank? }).to be(true)
  end

  it "summarizes only this tenant's manual campaign contribution within the selected dates" do
    account = AdvertisingAccount.create!(store: store, name: "Synthetic reporting", provider: "Meta")
    campaign = account.advertising_campaigns.create!(name: "Synthetic launch")
    campaign.advertising_performances.create!(date: now.to_date, spend_cents: 100, delivered_revenue_cents: 500,
      fulfillment_cost_cents: 150, delivered_orders: 2)
    campaign.advertising_performances.create!(date: now.to_date - 30, spend_cents: 999)
    foreign = AdvertisingAccount.create!(store: workspace, name: "Foreign reporting", provider: "Meta")
    foreign.advertising_campaigns.create!(name: "Foreign launch")
    row = metrics.campaigns.sole
    expect(row[:campaign]).to eq(campaign)
    expect(row[:metrics][:spend_cents]).to eq(100)
    expect(row[:contribution_cents]).to eq(250)
    expect(row[:roas]).to eq(5.0)
    expect(metrics.reported_ad_contribution).to eq(250)
    expect(metrics.average_gain_per_sale).to eq(125)
  end

  it "shows reported losses rather than unreported campaigns and distinguishes a reported zero" do
    account = AdvertisingAccount.create!(store: store, name: "Synthetic reporting", provider: "Meta")
    5.times { |index| account.advertising_campaigns.create!(name: "Unreported #{index}") }
    old = account.advertising_campaigns.create!(name: "Old reporting")
    old.advertising_performances.create!(date: now.to_date - 60, spend_cents: 5)
    expect(metrics.ad_reporting_present).to be(false)
    expect(metrics.campaigns).to be_empty
    loss = account.advertising_campaigns.create!(name: "Reported loss")
    loss.advertising_performances.create!(date: now.to_date, spend_cents: 123)
    result = metrics
    expect(result.ad_reporting_present).to be(true)
    expect(result.campaigns.sole[:campaign]).to eq(loss)
    expect(result.reported_ad_contribution).to eq(-123)
    zero = account.advertising_campaigns.create!(name: "Reported zero")
    zero.advertising_performances.create!(date: now.to_date)
    expect(metrics.campaigns.map { |row| row[:campaign] }).to eq([ zero, loss ])
  end

  it "assigns late UTC orders to their Casablanca calendar date" do
    local_midnight = now.beginning_of_day
    order(created_at: local_midnight, status: "delivered", total_cents: 123)
    order(created_at: local_midnight - 1.second, status: "delivered", total_cents: 456)
    result = metrics
    expect(result.daily_values.last[:delivered_values]).to eq("MAD" => 123)
    expect(result.daily_values[-2][:delivered_values]).to eq("MAD" => 456)
  end

  it "supports thirty-day windows and defaults invalid periods to seven days" do
    expect(metrics(period: "30").days).to eq(30)
    expect(metrics(period: "30").daily_values.length).to eq(30)
    expect(metrics(period: "invalid").days).to eq(7)
  end
it "derives verified net collected revenue and net profit from recorded cash, costs, carrier fees and expenses" do
  paid = order(status: "delivered", total_cents: 10_000, sendit_code: "SYN-1", sendit_fee: 20,
    collected_cents: 9_500, collected_at: now, refunded_cents: 500)
  paid.order_items.create!(product_name: "Synthetic", quantity: 2, unit_price_cents: 5_000, unit_cost_cents: 1_500, total_cents: 10_000)
  store.store_expenses.create!(spent_on: now.to_date, category: "packaging", amount_cents: 1_000)
  store.store_expenses.create!(spent_on: now.to_date - 30, category: "rent", amount_cents: 99_999)

  result = metrics
  expect(result.net_collected_values).to eq("MAD" => 9_000)
  expect(result.net_profit_values).to eq("MAD" => 3_000)
  expect(result.net_margin_rate).to eq(33.3)
  expect(result.cod_pending_count).to eq(0)
  expect(result.data_quality).to include(net_collected_revenue: :verified, net_profit: :verified)
end

it "marks money KPIs estimated when remittance is pending or a unit cost is missing, and never counts foreign tenants" do
  paid = order(status: "delivered", total_cents: 4_000, sendit_code: "SYN-2", sendit_fee: 10, collected_cents: 4_000, collected_at: now)
  paid.order_items.create!(product_name: "Uncosted", quantity: 1, unit_price_cents: 4_000, total_cents: 4_000)
  order(status: "delivered", total_cents: 2_000)
  foreign = workspace
  order(workspace: foreign, status: "delivered", total_cents: 7_777, collected_cents: 7_777, collected_at: now)

  result = metrics
  expect(result.net_collected_values).to eq("MAD" => 4_000)
  expect(result.cod_pending_count).to eq(1)
  expect(result.data_quality).to include(net_collected_revenue: :estimated, net_profit: :estimated)
end
end
