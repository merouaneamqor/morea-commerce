# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ozon::Sync do
  let(:store) { Store.create!(name: "Ozon Sync #{SecureRandom.hex(4)}", slug: "ozon-s-#{SecureRandom.hex(4)}", currency: "MAD") }
  let(:client) { instance_double(Ozon::Client) }
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
    account = store.delivery_accounts.create!(provider: "ozon", name: "Ozon", is_active: true, allow_open: true)
    account.credentials = { "api_key" => "44492", "api_secret" => "secret" }
    account.save!
    store.reload
    allow(Ozon::Cities).to receive(:match).and_return({ id: 1, name: "Casablanca", delivered_price: "25" })
  end

  describe "#push!" do
    it "creates the parcel and stores the tracking number" do
      expect(client).to receive(:add_parcel).and_return(
        "TRACKING-NUMBER" => "OZE123",
        "CITY_NAME" => "Casablanca",
        "DELIVERED-PRICE" => "25"
      )
      described_class.new(order, client: client).push!
      order.reload
      expect(order).to have_attributes(ozon_code: "OZE123", ozon_city_id: 1, ozon_city_name: "Casablanca", ozon_status: "NEW_PARCEL")
      expect(order.ozon_error).to be_nil
    end

    it "skips when a Sendit parcel already exists" do
      order.update!(sendit_code: "SEN1")
      expect(client).not_to receive(:add_parcel)
      described_class.new(order, client: client).push!
      expect(order.reload.ozon_code).to be_nil
    end
  end

  describe "#apply_status!" do
    it "advances the order when Ozon marks the parcel delivered" do
      order.update!(ozon_code: "OZE123", ozon_status: "IN_PROGRESS", status: "out_for_delivery")
      described_class.new(order, client: client).apply_status!("DELIVERED", fee: 25)
      order.reload
      expect(order).to have_attributes(status: "delivered", ozon_status: "DELIVERED", ozon_fee: 25)
    end

    it "marks returned for REFUSE" do
      order.update!(ozon_code: "OZE123", ozon_status: "IN_PROGRESS", status: "out_for_delivery")
      described_class.new(order, client: client).apply_status!("REFUSE", message: "Client refuses")
      expect(order.reload.status).to eq("returned")
    end
  end
end
