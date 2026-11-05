# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sendit connection from the Integrations API page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma", password: password, admin: true) }
  let(:keys) { { api_key: "pub-123", api_secret: "sec-456" } }
  let(:json) { JSON.parse(response.body) }

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def connect_sendit(**fields)
    post "/livraison/societes", params: { delivery_account: { provider: "sendit", name: "Sendit principal" }.merge(keys).merge(fields) }, headers: { "Accept" => "application/json" }
  end

  def refused(status: 401, kind: :invalid_keys, message: "Unauthorized", detail: "HTTP #{status}")
    Sendit::Client::Error.new(message, status: status, kind: kind, detail: detail)
  end

  describe "connecting" do
    before { allow(Sendit::Client).to receive(:verify!).and_return("session-token") }

    it "checks the keys with Sendit's login, stores them encrypted and returns the webhook URL" do
      connect_sendit
      expect(response).to have_http_status(:ok)
      expect(Sendit::Client).to have_received(:verify!).with(store, public_key: "pub-123", secret_key: "sec-456")
      account = store.delivery_accounts.sole
      expect(account).to have_attributes(provider: "sendit", name: "Sendit principal", code: "SEN1", is_active: true)
      expect(account.connected_at).to be_present
      expect(account.credentials).to eq("api_key" => "pub-123", "api_secret" => "sec-456")
      expect(account.credentials_ciphertext).not_to include("sec-456")
      expect(json).to eq("ok" => true, "webhook_url" => account.webhook_url)
      expect(json["webhook_url"]).to match(%r{\Ahttps?://[^/]+/webhooks/sendit/#{store.slug}\?token=[\w-]{30,}\z})
    end

    it "keeps the keys off the plain store columns but lets Morea's Sendit integration use them" do
      connect_sendit
      store.reload
      expect(store[:sendit_public_key]).to be_nil
      expect(store[:sendit_secret_key]).to be_nil
      expect(store.sendit_configured?).to be(true)
      expect(store).to have_attributes(sendit_public_key: "pub-123", sendit_secret_key: "sec-456")
      expect(Store.with_sendit).to include(store)
    end

    it "fetches the city list automatically and clears the cached session" do
      expect(Rails.cache).to receive(:delete).with("sendit:token:store:#{store.id}").and_call_original
      expect { connect_sendit }.to have_enqueued_job(SenditCitiesRefreshJob).with(store.id)
    end

    it "shows Sendit as connected on the Integrations page without ever rendering the secret key" do
      connect_sendit
      get "/integrations"
      account = store.delivery_accounts.sole
      expect(Nokogiri::HTML(response.body).at_css("[data-account='#{account.id}']").text).to include("Sendit principal", "SEN1", "Connectée")
      expect(response.body).not_to include("sec-456")
      accounts = JSON.parse(Nokogiri::HTML(response.body).at_css("[data-delivery-modal]")["data-accounts"])
      expect(accounts.first).to include("public_key" => "pub-123", "secret_hint" => "••••••••-456", "webhook_url" => account.webhook_url)
    end

    it "keeps the saved secret and the webhook token when editing without retyping the secret, and checks the keys again" do
      connect_sendit
      account = store.delivery_accounts.sole
      token = account.webhook_token
      patch "/livraison/societes/#{account.id}", params: { delivery_account: { name: "Sendit renommé", api_key: "pub-123", api_secret: "" } }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(Sendit::Client).to have_received(:verify!).with(store, public_key: "pub-123", secret_key: "sec-456").twice
      expect(account.reload).to have_attributes(name: "Sendit renommé", webhook_token: token)
      expect(account.credentials).to eq("api_key" => "pub-123", "api_secret" => "sec-456")
    end

    it "replaces the keys when new ones are typed" do
      connect_sendit
      account = store.delivery_accounts.sole
      patch "/livraison/societes/#{account.id}", params: { delivery_account: { name: "Sendit", api_key: "pub-999", api_secret: "sec-999" } }, headers: { "Accept" => "application/json" }
      expect(account.reload.credentials).to eq("api_key" => "pub-999", "api_secret" => "sec-999")
      expect(store.reload.sendit_secret_key).to eq("sec-999")
    end
  end

  describe "when the keys cannot be used" do
    it "shows a clear error and saves nothing when Sendit refuses the keys" do
      allow(Sendit::Client).to receive(:verify!).and_raise(refused)
      expect { connect_sendit }.not_to change(DeliveryAccount, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to eq("ok" => false, "code" => "invalid_keys", "detail" => "HTTP 401", "error" => I18n.t("seller_integrations.sendit.errors.invalid_keys"))
      expect(store.reload.sendit_configured?).to be(false)
    end

    it "gives each kind of failure its own message and technical detail, and saves nothing" do
      cases = {
        invalid_keys: [ refused(status: 422), /refusé ces clés/ ],
        blocked: [ refused(status: 403, kind: :blocked, detail: "HTTP 403 · Cloudflare · « Attention Required! | Cloudflare »"), /Cloudflare.*HTTP 403.*Vos clés ne sont pas en cause/ ],
        network: [ Sendit::Client::Error.new("Sendit unreachable: x", kind: :network, detail: "SocketError"), /Impossible de joindre Sendit depuis ce serveur/ ],
        unexpected: [ refused(status: 502, kind: :unexpected, detail: "HTTP 502"), /Réponse inattendue de Sendit \(HTTP 502\)/ ],
        rejected: [ refused(status: 403, kind: :rejected, message: "Compte désactivé", detail: "HTTP 403 · Compte désactivé"), /refusé la connexion \(HTTP 403\) : Compte désactivé/ ],
        none: [ Sendit::Client::Error.new("boom", status: 500), /Réponse inattendue de Sendit \(HTTP 500\)/ ]
      }
      cases.each do |kind, (error, message)|
        allow(Sendit::Client).to receive(:verify!).and_raise(error)
        expect { connect_sendit }.not_to change(DeliveryAccount, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        answer = JSON.parse(response.body)
        expect(answer["error"]).to match(message), "kind #{kind}: #{answer["error"]}"
        expect(answer["detail"]).to eq(error.detail) if error.detail
      end
      expect(cases.values.map { |_, message| message }.length).to eq(6)
      expect(%w[invalid_keys blocked network unexpected rejected].map { |key| I18n.t("seller_integrations.sendit.errors.#{key}", status: 1, message: "m") }.uniq.length).to eq(5)
    end

    it "never puts the keys in the error answer" do
      allow(Sendit::Client).to receive(:verify!).and_raise(refused(message: "bad key pub-123", detail: "HTTP 401"))
      connect_sendit
      expect(response.body).not_to include("sec-456")
    end

    it "needs both keys and does not call Sendit without them" do
      allow(Sendit::Client).to receive(:verify!)
      connect_sendit(api_secret: "")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq(I18n.t("seller_integrations.sendit.errors.missing_keys"))
      expect(Sendit::Client).not_to have_received(:verify!)
    end

    it "does not touch the saved keys when an edit is refused" do
      allow(Sendit::Client).to receive(:verify!).and_return("t")
      connect_sendit
      account = store.delivery_accounts.sole
      allow(Sendit::Client).to receive(:verify!).and_raise(refused)
      patch "/livraison/societes/#{account.id}", params: { delivery_account: { name: "x", api_key: "pub-bad", api_secret: "sec-bad" } }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.credentials).to eq("api_key" => "pub-123", "api_secret" => "sec-456")
    end
  end

  describe "deleting Sendit accounts" do
    let!(:account) do
      store.delivery_accounts.create!(provider: "sendit", name: "Synthetic Sendit", credentials: { "api_key" => "current-public", "api_secret" => "current-secret" })
    end

    before { store.update!(sendit_public_key: "legacy-public", sendit_secret_key: "legacy-secret", sendit_webhook_secret: "legacy-webhook") }

    it "does not reactivate legacy credentials when the last active connection is deleted" do
      [ "sendit:token:store:#{store.id}", Sendit::Districts.cache_key(store), "#{Sendit::Districts.cache_key(store)}:pickup" ].each do |key|
        expect(Rails.cache).to receive(:delete).with(key).and_call_original
      end
      expect { delete seller_delivery_account_path(account) }.to change(DeliveryAccount, :count).by(-1)
      expect(response).to have_http_status(:see_other)
      expect(store.reload.sendit_configured?).to be(false)
      expect(store).to have_attributes(sendit_webhook_secret: nil)
      expect(store[:sendit_public_key]).to be_nil
      expect(store[:sendit_secret_key]).to be_nil
    end

    it "preserves another active connection when an older active account is deleted" do
      remaining = store.delivery_accounts.create!(provider: "sendit", name: "Other Sendit", credentials: { "api_key" => "other-public", "api_secret" => "other-secret" })
      delete seller_delivery_account_path(account)
      expect(response).to have_http_status(:see_other)
      expect(store.reload.sendit_delivery_account).to eq(remaining)
      expect(store.sendit_secret_key).to eq("other-secret")
      expect(store[:sendit_secret_key]).to eq("legacy-secret")
    end

    it "keeps the effective legacy connection when an inactive historical account is deleted" do
      account.update!(is_active: false)
      delete seller_delivery_account_path(account)
      expect(response).to have_http_status(:see_other)
      expect(store.reload.sendit_configured?).to be(true)
      expect(store.sendit_secret_key).to eq("legacy-secret")
      expect(store.sendit_webhook_secret).to eq("legacy-webhook")
    end

    it "cannot delete an account belonging to a different workspace" do
      foreign_store = Store.create!(name: "Foreign #{suffix}", slug: "foreign-#{suffix}", currency: "MAD")
      foreign = foreign_store.delivery_accounts.create!(provider: "sendit", name: "Foreign Sendit", credentials: { "api_key" => "foreign-public", "api_secret" => "foreign-secret" })
      expect { delete seller_delivery_account_path(foreign) }.not_to change(DeliveryAccount, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the webhook" do
    let!(:account) do
      store.delivery_accounts.create!(provider: "sendit", name: "Sendit", credentials: keys.transform_keys(&:to_s), webhook_token: "tok-#{suffix}-abcdefghij", connected_at: Time.current)
    end
    let(:customer) { store.customers.create!(name: "Client", phone: "0612345678", email: "c-#{suffix}@example.test") }
    let!(:order) do
      store.orders.create!(customer: customer, number: "W#{suffix}", status: "confirmed", currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
        customer_city: "Fès", customer_address: "Rue 1", total_cents: 10_000, sendit_code: "PARCEL#{suffix}")
    end
    let(:payload) { { code: order.sendit_code, newStatus: "DELIVERED", message: "ok", deliverBy: nil } }

    def hook(slug: store.slug, token: nil, headers: {}, body: payload)
      post "/webhooks/sendit/#{slug}#{"?token=#{token}" if token}", params: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers)
    end

    def signature(secret, body) = OpenSSL::HMAC.hexdigest("SHA256", secret, body.to_json)

    it "accepts a call with the account's token and updates the parcel's order" do
      expect_any_instance_of(Sendit::Sync).to receive(:apply_status!).with("DELIVERED", message: "ok", deliver_by: nil)
      hook(token: account.webhook_token)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "order" => order.number)
    end

    it "rejects calls without a valid token" do
      expect_any_instance_of(Sendit::Sync).not_to receive(:apply_status!)
      hook
      expect(response).to have_http_status(:unauthorized)
      hook(token: "wrong-token")
      expect(response).to have_http_status(:unauthorized)
      hook(token: "")
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not accept a signature instead of the token, nor another workspace's token" do
      expect_any_instance_of(Sendit::Sync).not_to receive(:apply_status!)
      hook(headers: { "X-Sendit-Signature" => signature("sec-456", payload) })
      expect(response).to have_http_status(:unauthorized)
      other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
      foreign = other.delivery_accounts.create!(provider: "sendit", name: "Sendit", credentials: { "api_key" => "a", "api_secret" => "b" }, webhook_token: "foreign-#{suffix}-abcdefghij")
      hook(token: foreign.webhook_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "ignores a parcel it does not know, and an inactive account no longer authorizes" do
      hook(token: account.webhook_token, body: payload.merge(code: "UNKNOWN"))
      expect(JSON.parse(response.body)).to include("ignored" => true)
      account.update!(is_active: false)
      hook(token: account.webhook_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a malformed body with a valid token" do
      post "/webhooks/sendit/#{store.slug}?token=#{account.webhook_token}", params: "not json", headers: { "Content-Type" => "text/plain" }
      expect(response).to have_http_status(:bad_request)
    end

    it "keeps the older signed setup working for a workspace that has no Sendit account yet" do
      legacy = Store.create!(name: "Legacy #{suffix}", slug: "legacy-#{suffix}", currency: "MAD", sendit_secret_key: "legacy-secret", sendit_public_key: "legacy-public")
      expect_any_instance_of(Sendit::Sync).not_to receive(:apply_status!)
      hook(slug: legacy.slug)
      expect(response).to have_http_status(:unauthorized)
      hook(slug: legacy.slug, headers: { "X-Sendit-Signature" => signature("legacy-secret", payload) })
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ignored" => true)
    end

    it "answers 404 for an unknown workspace" do
      hook(slug: "nope-#{suffix}", token: account.webhook_token)
      expect(response).to have_http_status(:not_found)
    end
  end
end
