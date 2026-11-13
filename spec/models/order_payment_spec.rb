require "rails_helper"

RSpec.describe Order, "COD payment tracking" do
  let(:store) { Store.create!(slug: "pay-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca") }

  def build_order(status:, total: 10_000)
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: total,
      subtotal_cents: total, currency: "MAD", status: status)
  end

  it "records a collection once, only for delivered orders, within the order total" do
    expect { build_order(status: "in_transit").record_collection!(cents: 100) }.to raise_error(ArgumentError, /delivered/)
    delivered = build_order(status: "delivered")
    expect { delivered.record_collection!(cents: 10_001) }.to raise_error(ArgumentError, /between/)
    delivered.record_collection!(cents: 9_800)
    expect(delivered.reload).to have_attributes(collected_cents: 9_800, net_collected_cents: 9_800)
    expect(delivered.collected_at).to be_present
    expect(delivered.order_events.where(kind: "payment").count).to eq(1)
    expect { delivered.record_collection!(cents: 9_800) }.to raise_error(ArgumentError, /already/)
    expect(described_class.awaiting_remittance).not_to include(delivered)
  end

  it "records refunds only after collection and never beyond the collected amount" do
    delivered = build_order(status: "delivered")
    expect { delivered.record_refund!(cents: 100) }.to raise_error(ArgumentError, /Record the COD payment/)
    delivered.record_collection!(cents: 5_000)
    delivered.record_refund!(cents: 2_000)
    expect { delivered.record_refund!(cents: 3_001) }.to raise_error(ArgumentError, /cannot exceed/)
    expect { delivered.record_refund!(cents: 0) }.to raise_error(ArgumentError, /positive/)
    expect(delivered.reload.net_collected_cents).to eq(3_000)
  end

  it "lists delivered orders without collected cash as awaiting remittance" do
    pending_order = build_order(status: "delivered")
    build_order(status: "in_transit")
    expect(described_class.awaiting_remittance).to contain_exactly(pending_order)
  end
end
