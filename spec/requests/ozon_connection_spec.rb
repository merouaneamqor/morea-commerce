# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ozon Express connection from the Integrations API page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma", password: password, admin: true) }
  let(:json) { JSON.parse(response.body) }

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def connect_ozon(**fields)
    post "/livraison/societes",
         params: { delivery_account: { provider: "ozon", name: "Ozon principal", api_key: "44492", api_secret: "ozon-secret" }.merge(fields) },
         headers: { "Accept" => "application/json" }
  end

  describe "connecting" do
    before do
      allow(Ozon::Client).to receive(:verify!).and_return(true)
      allow(OzonCitiesRefreshJob).to receive(:perform_later)
    end

    it "checks the keys, stores them encrypted and returns the webhook URL" do
      connect_ozon
      expect(response).to have_http_status(:ok)
      expect(Ozon::Client).to have_received(:verify!).with(store, customer_id: "44492", api_key: "ozon-secret")
      account = store.delivery_accounts.sole
      expect(account).to have_attributes(provider: "ozon", name: "Ozon principal", code: "OZO1", is_active: true)
      expect(account.connected_at).to be_present
      expect(account.credentials).to eq("api_key" => "44492", "api_secret" => "ozon-secret")
      expect(account.credentials_ciphertext).not_to include("ozon-secret")
      expect(json).to eq("ok" => true, "webhook_url" => account.webhook_url, "ships_by_default" => true)
      expect(account.ships_by_default?).to be(true)
      expect(json["webhook_url"]).to match(%r{\Ahttps?://[^/]+/webhooks/ozon/#{store.slug}\?token=[\w-]{30,}\z})
      expect(store.reload.ozon_configured?).to be(true)
      expect(OzonCitiesRefreshJob).to have_received(:perform_later).with(store.id)
    end

    it "rejects missing keys without saving" do
      connect_ozon(api_secret: "")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["ok"]).to eq(false)
      expect(store.delivery_accounts).to be_empty
    end

    it "surfaces an invalid_keys error from the API check" do
      allow(Ozon::Client).to receive(:verify!).and_raise(
        Ozon::Client::Error.new("bad keys", status: 401, kind: :invalid_keys, detail: "HTTP 401")
      )
      connect_ozon(api_secret: "bad")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("ok" => false, "code" => "invalid_keys")
      expect(store.delivery_accounts).to be_empty
    end
  end
end
