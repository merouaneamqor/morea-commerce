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
    allow(Ameex::Cities).to receive(:match).and_return({ id: 129, name: "Casablanca" })
  end

  it "creates the parcel and stores the code" do
    expect(client).to receive(:add_parcel).and_return("code" => "SBX-11BC3E72", "msg" => "Sandbox parcel created.", "sandbox" => 1)
    described_class.new(order, client: client).push!
    expect(order.reload).to have_attributes(ameex_code: "SBX-11BC3E72", ameex_status: "NEW_PARCEL", ameex_city_id: 129)
  end

  it "marks delivered from webhook status" do
    order.update!(ameex_code: "SBX-1", ameex_status: "IN_PROGRESS", status: "out_for_delivery")
    described_class.new(order, client: client).apply_status!("DELIVERED", message: "OK")
    expect(order.reload).to have_attributes(status: "delivered", ameex_status: "DELIVERED", ameex_message: "OK")
  end

  it "refreshes status from parcel info" do
    order.update!(ameex_code: "SBX-1", ameex_status: "NEW_PARCEL", status: "confirmed")
    expect(client).to receive(:parcel_info).with("SBX-1").and_return(
      "code" => "SBX-1", "statut" => "PICKED_UP", "statut_name" => "Ramassé"
    )
    described_class.new(order, client: client).refresh!
    expect(order.reload.ameex_status).to eq("PICKED_UP")
  end

  describe ".labels_for" do
    it "merges remote status names from Delivery/Parcels/Statuts" do
      allow(Ameex::Client).to receive(:configured?).and_return(true)
      allow_any_instance_of(Ameex::Client).to receive(:statuses).and_return(
        "DELIVERED" => { "name" => "Livré", "color" => "#9ccc65" },
        "IN_PROGRESS" => { "name" => "En cours", "color" => "#ffba57" }
      )
      Rails.cache.clear
      labels = described_class.labels_for(store)
      expect(labels["DELIVERED"]).to eq("Livré")
      expect(described_class.label("DELIVERED", store: store)).to eq("Livré")
    end
  end
end
