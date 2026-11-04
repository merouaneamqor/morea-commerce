# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Order fees frozen for accounting" do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { Store.create!(name: "Frais #{suffix}", slug: "frais-#{suffix}", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test") }

  before { allow(OrderStatusJob).to receive(:perform_later) }

  def order(status: "in_transit", sendit_fee: nil)
    store.orders.create!(customer: customer, number: "F#{SecureRandom.hex(4)}", status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 10_000, total_cents: 10_000, sendit_fee: sendit_fee)
  end

  def move(record, status)
    record.send(:apply_status_change!, status, force: true, sync_delivery: false)
    record.reload
  end

  def account(provider, delivery_fee:, return_fee:, active: true)
    store.delivery_accounts.create!(provider: provider, name: provider, account_type: "normal", is_active: active, delivery_fee: delivery_fee, return_fee: return_fee)
  end

  it "freezes the carrier's fee of the parcel, in whole centimes, when the order is delivered" do
    record = move(order(sendit_fee: BigDecimal("24.50")), "delivered")
    expect(record.delivery_fee_cents).to eq(2_450)
    expect(record.return_fee_cents).to be_nil
  end

  it "freezes the return fee when the order is returned, and never counts it as a delivery fee" do
    record = move(order(sendit_fee: BigDecimal("18")), "returned")
    expect(record.return_fee_cents).to eq(1_800)
    expect(record.delivery_fee_cents).to be_nil
  end

  it "rounds half a centime up, once" do
    expect(move(order(sendit_fee: BigDecimal("12.345")), "delivered").delivery_fee_cents).to eq(1_235)
  end

  it "does not change when the carrier's live fee changes afterwards" do
    record = move(order(sendit_fee: BigDecimal("25")), "delivered")
    record.update!(sendit_fee: BigDecimal("99"))
    record.freeze_fees!
    expect(record.reload.delivery_fee_cents).to eq(2_500)
  end

  it "uses the one active delivery account's default fee when the carrier did not report one" do
    account("ozon", delivery_fee: 30, return_fee: 12.5)
    account("ameex", delivery_fee: 99, return_fee: 99, active: false)
    expect(move(order, "delivered").delivery_fee_cents).to eq(3_000)
    expect(move(order, "returned").return_fee_cents).to eq(1_250)
  end

  it "leaves the fee unknown (nil) rather than guess when accounts disagree or there is none" do
    expect(move(order, "delivered").delivery_fee_cents).to be_nil
    account("ozon", delivery_fee: 30, return_fee: 10)
    account("ameex", delivery_fee: 25, return_fee: 10)
    expect(move(order, "delivered").delivery_fee_cents).to be_nil
    expect(move(order, "returned").return_fee_cents).to eq(1_000) # both accounts agree on the return fee
  end

  it "fills a missing fee as soon as the carrier reports it, and never overwrites a frozen one" do
    record = move(order, "delivered")
    expect(record.delivery_fee_cents).to be_nil
    record.update!(sendit_fee: BigDecimal("22"))
    record.freeze_fees!
    expect(record.reload.delivery_fee_cents).to eq(2_200)
    record.update!(sendit_fee: BigDecimal("40"))
    record.freeze_fees!
    expect(record.reload.delivery_fee_cents).to eq(2_200)
  end

  it "does nothing for an order that is neither delivered nor returned" do
    record = order(sendit_fee: BigDecimal("25"))
    record.freeze_fees!
    expect(record.reload).to have_attributes(delivery_fee_cents: nil, return_fee_cents: nil)
  end

  it "rejects a negative frozen fee at the database level" do
    record = order
    expect { record.update_columns(delivery_fee_cents: -1) }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
