# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ameex webhook", type: :request do
  let(:store) { Store.create!(name: "Ameex Hook #{SecureRandom.hex(4)}", slug: "ameex-h-#{SecureRandom.hex(4)}", currency: "MAD") }
  let(:account) do
    a = store.delivery_accounts.create!(provider: "ameex", name: "Ameex", is_active: true)
    a.credentials = { "api_key" => "id-1", "api_secret" => "key-1" }
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
      ameex_code: "AMX999",
      ameex_status: "IN_PROGRESS",
      confirmed_at: Time.current
    )
  end

  it "updates the order from the form-encoded webhook" do
    account
    post "/webhooks/ameex/#{store.slug}?token=#{account.webhook_token}",
         params: { CODE: "AMX999", STATUT: "DELIVERED", STATUT_NAME: "Livré", COMMENT: "OK" }

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "delivered", ameex_status: "DELIVERED", ameex_message: "OK")
  end

  it "rejects calls without the webhook token" do
    account
    post "/webhooks/ameex/#{store.slug}", params: { CODE: "AMX999", STATUT: "DELIVERED" }
    expect(response).to have_http_status(:unauthorized)
  end
end
