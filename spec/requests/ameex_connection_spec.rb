# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ameex connection from the Integrations API page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma", password: password, admin: true) }
  let(:json) { JSON.parse(response.body) }

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def connect_ameex(**fields)
    post "/livraison/societes",
         params: { delivery_account: { provider: "ameex", name: "Ameex principal", api_key: "id-1", api_secret: "key-1" }.merge(fields) },
         headers: { "Accept" => "application/json" }
  end

  describe "connecting" do
    before do
      allow(Ameex::Client).to receive(:verify!).and_return(true)
      allow(AmeexCitiesRefreshJob).to receive(:perform_later)
    end

    it "checks the keys, stores them encrypted and returns the webhook URL" do
      connect_ameex
      expect(response).to have_http_status(:ok)
      expect(Ameex::Client).to have_received(:verify!).with(store, api_id: "id-1", api_key: "key-1")
      account = store.delivery_accounts.sole
      expect(account).to have_attributes(provider: "ameex", name: "Ameex principal", code: "AME1", is_active: true)
      expect(account.credentials).to eq("api_key" => "id-1", "api_secret" => "key-1")
      expect(json).to include("ok" => true, "ships_by_default" => true)
      expect(json["webhook_url"]).to match(%r{/webhooks/ameex/#{store.slug}\?token=})
      expect(store.reload.ameex_configured?).to be(true)
      expect(store.ships_with?(:ameex)).to be(true)
      expect(account.connected?).to be(true)
    end

    it "rejects missing keys without saving" do
      connect_ameex(api_secret: "")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["ok"]).to eq(false)
      expect(store.delivery_accounts).to be_empty
    end

    it "does not mark connected when Ameex refuses the keys" do
      allow(Ameex::Client).to receive(:verify!).and_raise(
        Ameex::Client::Error.new("bad keys", status: 401, kind: :invalid_keys, detail: "HTTP 401 · login error")
      )
      expect { connect_ameex(api_secret: "bad") }.not_to change(DeliveryAccount, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("ok" => false, "code" => "invalid_keys")
      expect(store.reload.ameex_configured?).to be(false)
    end
  end
end
