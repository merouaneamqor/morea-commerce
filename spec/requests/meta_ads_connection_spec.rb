# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Meta Ads connection", type: :request do
  let(:password) { "synthetic-meta-password-123" }
  let(:store) { Store.create!(slug: "meta-req-#{SecureRandom.hex(5)}", name: "Synthetic Meta workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "meta-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:other_store) { Store.create!(slug: "meta-oth-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD", storefront_enabled: false) }
  let(:token) { "synthetic-meta-access-token" }
  let(:accounts) { [ { id: "act_11", name: "Main", currency: "EUR", timezone_name: "Europe/Paris" }, { id: "act_22", name: "Second", currency: "USD", timezone_name: "UTC" } ] }
  let(:transport) do
    lambda do |uri, request|
      body = case uri.path
      when %r{/oauth/access_token}
        URI.decode_www_form(request.body).to_h["grant_type"] == "fb_exchange_token" ? { access_token: token, expires_in: 5_184_000 } : { access_token: "synthetic-short" }
      when %r{/debug_token} then { data: { is_valid: true, scopes: %w[ads_read], user_id: "42", expires_at: 30.days.from_now.to_i } }
      when %r{/me/adaccounts} then { data: accounts }
      else raise "Unexpected #{uri}"
      end
      Struct.new(:code, :body, :to_hash).new("200", body.to_json, {})
    end
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_APP_ID").and_return("synthetic-app-id")
    allow(ENV).to receive(:[]).with("META_APP_SECRET").and_return("synthetic-app-secret")
    %i[Authorizer AccountDiscovery].each do |name|
      klass = MetaAds.const_get(name)
      allow(klass).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: transport) }
    end
  end

  def sign_in(user = staff, host = "#{store.slug}.#{Store.base_domain}")
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def start_authorization
    post "/admin/meta-ads/connect"
    expect(response).to have_http_status(:see_other)
    expect(URI(response.location).host).to eq("www.facebook.com")
    Rack::Utils.parse_nested_query(URI(response.location).query).fetch("state")
  end

  def connect!
    sign_in
    state = start_authorization
    get "/admin/meta-ads/callback", params: { code: "synthetic-code", state: state }
  end

  it "requires a signed-in store operator and a current store" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin/meta-ads"
    expect(response).to redirect_to("/admin/login")
    post "/admin/meta-ads/connect"
    expect(response).to redirect_to("/admin/login")
  end

  it "connects, lists accounts and never renders the token" do
    connect!
    expect(response).to redirect_to("/admin/meta-ads")
    connection = store.reload.meta_ads_connection
    expect(connection).to have_attributes(status: "active", granted_scopes: %w[ads_read])
    expect(store.meta_ads_ad_accounts.pluck(:meta_ad_account_id)).to match_array(%w[act_11 act_22])

    follow_redirect!
    expect(response.body).to include("act_11", "EUR", "Europe/Paris")
    expect(response.body).not_to include(token, connection.access_token_ciphertext)
  end

  it "selects several accounts and shows them as waiting for their first sync" do
    connect!
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11 act_22] }
    expect(response).to redirect_to("/admin/meta-ads")
    expect(store.meta_ads_ad_accounts.selected.count).to eq(2)
    follow_redirect!
    expect(response.body).to include(I18n.t("meta_ads.sync_status.pending"))
  end

  it "rejects a callback with a forged or reused state without changing the connection" do
    sign_in
    start_authorization
    get "/admin/meta-ads/callback", params: { code: "synthetic-code", state: SecureRandom.hex(32) }
    expect(response).to redirect_to("/admin/meta-ads")
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
  end

  it "never lets one store read, select or sync another store's accounts" do
    other_connection = MetaAds::Connection.create!(store: other_store, access_token: "synthetic-other-token")
    foreign = other_store.meta_ads_ad_accounts.create!(connection: other_connection, meta_ad_account_id: "act_77", name: "Foreign", currency: "EUR", timezone_name: "UTC")
    connect!

    get "/admin/meta-ads"
    expect(response.body).not_to include("act_77", "Foreign")
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_77], id: foreign.id }
    expect(response).to redirect_to("/admin/meta-ads")
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.unknown_account"))
    expect(foreign.reload.selected).to be(false)
  end

  it "marks the connection for reconnection when Meta revokes access and keeps history" do
    connect!
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11] }
    revoked = ->(_uri, _request) { Struct.new(:code, :body, :to_hash).new("400", { error: { code: 190, message: "Token revoked" } }.to_json, {}) }
    allow(MetaAds::AccountDiscovery).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: revoked) }

    post "/admin/meta-ads/refresh"
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.reauthorization_required"))
    connection = store.reload.meta_ads_connection
    expect(connection).to have_attributes(status: "needs_reauthorization", access_token: nil)
    expect(store.meta_ads_ad_accounts.count).to eq(2)
    expect(store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11").sync_status).to eq("needs_reauthorization")

    get "/admin/meta-ads"
    expect(response.body).to include(I18n.t("meta_ads.reauthorize_note"), I18n.t("meta_ads.reconnect"))
    allow(MetaAds::AccountDiscovery).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: transport) }
    state = start_authorization
    get "/admin/meta-ads/callback", params: { code: "synthetic-code", state: state }
    expect(MetaAds::Connection.where(store: store).count).to eq(1)
    expect(store.reload.meta_ads_connection.status).to eq("active")
  end

  it "disconnects by deleting the token and keeping synced accounts" do
    connect!
    delete "/admin/meta-ads/connection"
    expect(response).to redirect_to("/admin/meta-ads")
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil, access_token_ciphertext: nil)
    expect(store.meta_ads_ad_accounts.count).to eq(2)
  end

  %w[fr ar].each do |locale|
    it "renders the page in #{locale}" do
      connect!
      I18n.with_locale(locale) { @expected = I18n.t("meta_ads.title") }
      store.update!(admin_locale: locale) if store.respond_to?(:admin_locale=)
      get "/admin/meta-ads", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(I18n.t("meta_ads.title", locale: locale)).not_to match(/translation missing/)
    end
  end
end
