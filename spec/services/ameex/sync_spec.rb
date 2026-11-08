# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ameex::Sync do
  let(:store) { Store.create!(name: "Ameex Sync #{SecureRandom.hex(4)}", slug: "ameex-s-#{SecureRandom.hex(4)}", currency: "MAD") }
  let(:client) { instance_double(Ameex::Client) }
  let(:customer) { store.customers.create!(name: "Karim", phone: "0612345678") }
  let(:order) do
    store.orders.create!(
      customer: customer,
      status: "confirmed",
      customer_name: "Karim",
      customer_phone: "0612345678",
      customer_city: "Casablanca",
      customer_address: "Rue Hassan II",
      total_cents: 25_000,
      currency: "MAD",
      confirmed_at: Time.current
    )
  end

  before do
    account = store.delivery_accounts.new(provider: "ameex", name: "Ameex", is_active: true, ships_by_default: true)
    account.credentials = { "api_key" => "id-1", "api_secret" => "key-1" }
    account.save!
    store.reload
    allow(Ameex::Cities).to receive(:match).and_return({ id: 12, name: "Casablanca" })
  end

  it "creates the parcel and stores the code" do
    expect(client).to receive(:add_parcel).and_return("CODE" => "AMX123", "STATUT" => "NEW_PARCEL")
    described_class.new(order, client: client).push!
    expect(order.reload).to have_attributes(ameex_code: "AMX123", ameex_status: "NEW_PARCEL", ameex_city_id: 12)
  end

  it "marks delivered from webhook status" do
    order.update!(ameex_code: "AMX123", ameex_status: "IN_PROGRESS", status: "out_for_delivery")
    described_class.new(order, client: client).apply_status!("DELIVERED", message: "OK")
    expect(order.reload).to have_attributes(status: "delivered", ameex_status: "DELIVERED", ameex_message: "OK")
  end
end
