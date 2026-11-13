# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ozon webhook", type: :request do
  let(:store) { Store.create!(name: "Ozon Hook #{SecureRandom.hex(4)}", slug: "ozon-h-#{SecureRandom.hex(4)}", currency: "MAD") }
  let(:account) do
    a = store.delivery_accounts.create!(provider: "ozon", name: "Ozon", is_active: true)
    a.credentials = { "api_key" => "44492", "api_secret" => "secret" }
    a.generate_webhook_token
    a.save!
    a
  end
  let(:customer) { store.customers.create!(name: "Karim", phone: "0612345678") }
  let!(:order) do
    store.orders.create!(
      customer: customer,
      status: "out_for_delivery",
      customer_name: "Karim",
      customer_phone: "0612345678",
      customer_city: "Casablanca",
      customer_address: "Rue 1",
      total_cents: 10_000,
      currency: "MAD",
      ozon_code: "OZE999",
      ozon_status: "IN_PROGRESS",
      confirmed_at: Time.current
    )
  end

  it "updates the order from the webhook payload" do
    account
    post "/webhooks/ozon/#{store.slug}?token=#{account.webhook_token}",
         params: { orderid: "OZE999", orderStatus: "DELIVERED", note: "OK" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "delivered", ozon_status: "DELIVERED", ozon_message: "OK")
  end

  it "rejects calls without the webhook token" do
    account
    post "/webhooks/ozon/#{store.slug}",
         params: { orderid: "OZE999", orderStatus: "DELIVERED" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
